# frozen_string_literal: true

require "rspec/core"
require "shellwords"

require_relative "capturing_formatter/version"
require_relative "capturing_formatter/configuration"
require_relative "capturing_formatter/sanitizer"
require_relative "capturing_formatter/stream_proxy"
require_relative "capturing_formatter/windows_terminal"
require_relative "capturing_formatter/renderer"
require_relative "capturing_formatter/windows_command_line"

module RSpec
  # Interprets RSpec notifications and attributes captured writes; Renderer owns presentation.
  class CapturingFormatter
    class << self
      def configuration
        @configuration ||= CapturingFormatter::Configuration.new
      end

      def configure
        yield(configuration)
      end
    end

    attr_reader :output

    def initialize(output, capture_manager: CapturingFormatter::CaptureManager.instance)
      @output = output
      @manager = capture_manager
      manager_was_active = @manager.active?
      manager_generation = @manager.generation
      @renderer = CapturingFormatter::Renderer.new(
        output,
        self.class.configuration,
        capture_manager: @manager
      )
      @groups = []
      @seen_groups = {}
      @current_example = nil
      @started = false
      @suite_heading_emitted = false
      @report_visible = false
      @failed_reruns = []
      @seed_notification = nil
      @lease = @manager.activate(output, self)
    # Construction mutates process-global streams, so clean them up even for exceptions outside StandardError.
    # standard:disable Lint/RescueException
    rescue Exception
      # standard:enable Lint/RescueException
      if defined?(@lease) && @lease
        @manager.deactivate(@lease)
      elsif @manager && !manager_was_active
        @manager.rollback_if_unchanged(manager_generation)
      end
      raise
    end

    def start(notification)
      with_capture_lock do
        @started = true
        @count = notification.count if notification.respond_to?(:count)
        @load_time = notification.load_time if notification.respond_to?(:load_time)
      end
    end

    def example_group_started(notification)
      with_capture_lock { @groups << notification.group }
    end

    def example_group_finished(_notification)
      with_capture_lock { @groups.pop }
    end

    def example_started(notification)
      with_capture_lock do
        example = notification.example
        @groups.each { |group| @seen_groups[group.object_id] = true }
        @current_example = example
        @report_visible = true
        @renderer.example_started(path_for(example))
      end
    end

    def example_passed(notification)
      with_capture_lock { finish_example(notification.example, :passed) }
    end

    def example_failed(notification)
      with_capture_lock do
        example = notification.example
        finish_example(example, :failed, notification)
      end
    end

    def example_pending(notification)
      with_capture_lock do
        example = notification.example
        reason = example.execution_result.pending_message.to_s
        # RSpec represents a skipped example as pending without a pending exception.
        skipped = example.execution_result.pending_exception.nil?
        @renderer.pending(
          reason,
          rerun_command(example),
          skipped: skipped,
          run_time: example.execution_result.run_time
        )
        unless skipped || pending_failure_output == :skip
          lines = failure_lines(notification, example)
          if pending_failure_output == :no_backtrace
            # RSpec's formatted backtrace lines start with `# ` after styling and indentation are removed.
            lines = lines.reject { |line| strip_ansi(line.to_s).lstrip.start_with?("# ") }
          end
          @renderer.failure(lines)
        end
        @current_example = nil
      end
    end

    def message(notification)
      with_capture_lock do
        inside = !@current_example.nil?
        @renderer.message(notification.message, inside_example: inside)
        @report_visible = true
      end
    end

    def stop(_notification)
      with_capture_lock { @manager.deactivate(@lease) }
    end

    def dump_profile(notification)
      with_capture_lock { @renderer.profile(notification) }
    end

    def dump_summary(notification)
      with_capture_lock do
        total = notification.respond_to?(:example_count) ? notification.example_count : notification.examples.to_i
        failed = notification.respond_to?(:failure_count) ? notification.failure_count : notification.failed_examples.to_i
        pending = notification.respond_to?(:pending_count) ? notification.pending_count : notification.pending_examples.to_i
        @renderer.summary(
          total: total,
          succeeded: total - failed - pending,
          failed: failed,
          pending: pending,
          duration: notification.duration,
          load_time: notification.load_time,
          errors: notification.errors_outside_of_examples_count
        )
        @renderer.reruns(@failed_reruns.uniq)
        if @seed_notification&.respond_to?(:seed_used?) && @seed_notification.seed_used?
          @renderer.seed(@seed_notification.seed)
        end
      end
    end

    def seed(notification)
      with_capture_lock { @seed_notification = notification }
    end

    def close(_notification = nil)
      with_capture_lock { @manager.deactivate(@lease) }
    end

    def capture(source, value, encoding, nonblocking: false)
      with_capture_lock do
        if @current_example
          @renderer.capture(source.to_s, value, encoding, nonblocking: nonblocking)
        else
          ensure_suite_or_context
          label = (source == :stdout) ? "suite stdout" : "suite stderr"
          @renderer.capture(label, value, encoding, nonblocking: nonblocking)
        end
      end
    end

    def finish_capture
      with_capture_lock { @renderer.finish_capture }
    end

    def flush_pending
      with_capture_lock { @renderer.flush_pending }
    end

    private

    def finish_example(example, status, notification = nil)
      @renderer.result(status, example.execution_result.run_time)
      if notification && status == :failed
        @renderer.rerun_inline(rerun_command(example))
        @renderer.failure(failure_lines(notification, example))
        @failed_reruns << rerun_command(example)
      elsif status == :failed
        @failed_reruns << rerun_command(example)
      end
      @current_example = nil
    end

    def with_capture_lock(&block)
      # RSpec notifications and captured writes share this lock so report fragments cannot interleave.
      @manager.synchronize(&block)
    end

    # Normalize presenter output for inline rendering, including older presenters that reject a colorizer.
    def failure_lines(notification, example)
      lines = if notification.respond_to?(:fully_formatted_lines)
        notification.fully_formatted_lines(nil, @renderer.failure_colorizer)
      else
        Array(notification.message_lines)
      end
      lines = Array(lines)
      lines.shift while lines.first.to_s.empty?
      description = example.full_description.to_s if example.respond_to?(:full_description)
      if description && !description.empty? && strip_ansi(lines.first.to_s).strip == description
        lines.shift
      end
      lines
    rescue ArgumentError
      value = Array(notification.fully_formatted_lines(nil))
      value.shift while value.first.to_s.empty?
      value
    end

    def ensure_suite_or_context
      # Suite output gets a heading only when it starts the report; unseen active groups get context headings.
      if @groups.empty?
        heading = !@suite_heading_emitted && !@report_visible
        @renderer.suite_started(heading: heading)
        @suite_heading_emitted = true if heading
      else
        heading = @groups.any? { |group| !@seen_groups[group.object_id] }
        @renderer.context_started(context_path, heading: heading)
        @groups.each { |group| @seen_groups[group.object_id] = true }
      end
      @report_visible = true
    end

    def context_path
      components = @groups.map { |group| group.description.to_s }.reject(&:empty?)
      components.join(path_separator)
    end

    def path_for(example)
      components = @groups.map { |group| group.description.to_s }.reject(&:empty?)
      description = example.description.to_s
      description = rerun_argument(example) if description.empty?
      (components + [description]).reject(&:empty?).join(path_separator)
    end

    def rerun_command(example)
      argument = rerun_argument(example)
      return CapturingFormatter::WindowsCommandLine.rerun_command(argument) if Gem.win_platform?

      "rspec #{Shellwords.escape(argument)}"
    end

    def rerun_argument(example)
      # A duplicated location cannot identify one example, so prefer its stable RSpec ID.
      location = if example.respond_to?(:location_rerun_argument)
        example.location_rerun_argument
      elsif example.respond_to?(:location)
        example.location
      else
        example.id
      end
      duplicate = if defined?(RSpec.world) && RSpec.world.respond_to?(:all_examples)
        RSpec.world.all_examples.count { |item| item.location_rerun_argument == location } > 1
      end
      (duplicate && example.respond_to?(:id)) ? example.id : location
    end

    def path_separator
      # Prefer a readable ASCII separator when the destination cannot encode the configured value.
      separator = self.class.configuration.separator
      encoding = @renderer.output.external_encoding if @renderer.output.respond_to?(:external_encoding)
      return separator unless encoding

      separator.encode(encoding)
      separator
    rescue EncodingError, TypeError
      " > "
    end

    def pending_failure_output
      # An explicit formatter setting wins; otherwise inherit RSpec's setting when available.
      configuration = self.class.configuration
      return configuration.pending_failure_output if configuration.pending_failure_output_configured?
      return configuration.pending_failure_output unless defined?(RSpec) &&
        RSpec.respond_to?(:configuration) && RSpec.configuration.respond_to?(:pending_failure_output)

      RSpec.configuration.pending_failure_output
    end

    def strip_ansi(value)
      value.gsub(/\e\[[0-?]*+[ -\/]*+[@-~]/, "")
    end
  end

  # Requiring the formatter installs inactive pass-through proxies before RSpec constructs it.
  CapturingFormatter::CaptureManager.install!
  # Failure and expected-pending details are rendered inline, so their dump events are intentionally omitted.
  RSpec::Core::Formatters.register(
    CapturingFormatter,
    :start,
    :example_group_started,
    :example_group_finished,
    :example_started,
    :example_passed,
    :example_failed,
    :example_pending,
    :message,
    :stop,
    :dump_profile,
    :dump_summary,
    :seed,
    :close
  )
end
