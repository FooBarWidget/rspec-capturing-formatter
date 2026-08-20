require "stringio"

module RSpec
  class BetterFormatter
    class Renderer
      RESET = "\e[0m"
      COLORS = {
        green: "\e[32m",
        red: "\e[31m",
        yellow: "\e[33m",
        cyan: "\e[36m",
        bold: "\e[1m"
      }.freeze

      attr_reader :output

      def initialize(output, configuration)
        @output = output || StringIO.new
        @configuration = configuration
        @entry_started = false
        @entry_kind = nil
        @entry_path = nil
        @capture_source = nil
        @capture_open = false
        @capture_styled = false
        @sanitizers = {}
      end

      def failure_colorizer
        FailureColorizer.new(self)
      end

      def example_started(path)
        finish_capture
        begin_entry
        @entry_kind = :example
        @entry_path = path
        line(path)
      end

      def context_started(path)
        return if @entry_kind == :context && @entry_path == path

        finish_capture
        begin_entry
        @entry_kind = :context
        @entry_path = path
        line(path)
      end

      def suite_started
        return if @entry_kind == :suite

        finish_capture
        begin_entry
        @entry_kind = :suite
        @entry_path = "RSpec suite"
        line("RSpec suite")
      end

      def capture(source, value, encoding = nil)
        if @capture_source != source
          finish_capture
          @capture_source = source
        end

        text = (@sanitizers[source] ||= Sanitizer.new).process(value, encoding)
        emit_captured_text(source, text)
      end

      def message(lines, inside_example: false)
        finish_capture
        unless inside_example && @entry_kind == :example
          begin_entry
          @entry_kind = :rspec
          @entry_path = nil
        end
        lines = lines.to_s.lines
        lines = [""] if lines.empty?
        lines.each { |entry| line("  rspec | #{entry.chomp}") }
      end

      def result(status, run_time = nil)
        finish_capture
        label, color = status_label(status)
        suffix = duration_suffix(run_time)
        line("  #{style(label, color)}#{suffix}")
      end

      def pending(reason, location, skipped: false)
        finish_capture
        label, color = status_label(skipped ? :skipped : :pending)
        line("  #{style(label, color)}")
        line("  reason | #{reason}") unless reason.to_s.empty?
        line("  rerun | #{location}") unless location.to_s.empty?
      end

      def failure(notification_lines)
        finish_capture
        notification_lines.each do |entry|
          value = entry.to_s.chomp
          line(value.empty? ? "" : "  #{value}")
        end
      end

      def summary(total:, succeeded:, failed:, pending:, duration:, load_time:, errors: 0)
        finish_capture
        begin_entry
        @entry_kind = :summary
        @entry_path = nil
        line(style("Summary", :bold))
        line("  #{total} total  #{succeeded} succeeded  #{failed} failed  #{pending} pending")
        line("  Finished in #{format_seconds(duration)}  |  files loaded in #{format_milliseconds(load_time)}")
        line("  #{errors} errors outside examples") if errors.to_i.positive?
      end

      def profile(notification)
        examples = notification.respond_to?(:slowest_examples) ? notification.slowest_examples : []
        return if examples.nil? || examples.empty?

        finish_capture
        begin_entry
        @entry_kind = :profile
        @entry_path = nil
        line("Profile")
        examples.each do |example|
          description = example.respond_to?(:full_description) ? example.full_description : example.to_s
          runtime = example.respond_to?(:execution_result) ? example.execution_result.run_time : nil
          line("  #{format_seconds(runtime)}  #{description}")
        end
      end

      def reruns(commands)
        return if commands.empty?

        finish_capture
        begin_entry
        @entry_kind = :reruns
        @entry_path = nil
        line("Failed examples")
        commands.each { |command| line("  #{command}") }
      end

      def seed(seed)
        return if seed.nil?

        finish_capture
        begin_entry
        @entry_kind = :seed
        @entry_path = nil
        line("  Randomized with seed #{seed}")
      end

      def finish_capture
        return unless @capture_open || @capture_source || @capture_styled

        sanitizer = @sanitizers[@capture_source]
        trailing = sanitizer&.finish.to_s
        emit_captured_text(@capture_source, trailing) unless trailing.empty?
        if @capture_open
          write_raw(RESET) if color_enabled? || @capture_styled
          write_raw("\n")
        elsif @capture_styled
          write_raw(RESET)
        end
        @capture_open = false
        @capture_source = nil
        @capture_styled = false
      end

      private

      def emit_captured_text(source, text)
        return if text.empty?

        @capture_styled = true if text.match?(/\e\[[0-9;]*m/)

        begin_entry unless @entry_started
        prefix = "  #{source} | "
        unless @capture_open
          write_raw(RESET) if color_enabled?
          write_raw(prefix)
          @capture_open = true
        end

        parts = text.split("\n", -1)
        parts.each_with_index do |part, index|
          write_raw(part) unless part.empty?
          next unless index < parts.length - 1

          write_raw(RESET) if color_enabled?
          write_raw("\n")
          write_raw(prefix) unless index == parts.length - 2 && parts.last.empty?
        end

        if text.end_with?("\n")
          @capture_open = false
          @capture_source = nil
        end
      end

      def begin_entry
        finish_capture
        write_raw("\n") if @entry_started
        @entry_started = true
      end

      def line(value)
        write_raw(RESET) if color_enabled?
        write_raw(style(value.to_s, nil))
        write_raw("\n")
      end

      def write_raw(value)
        return if value.nil? || value.empty?

        text = encode_for_output(value)
        if defined?(CaptureManager)
          CaptureManager.instance.bypass { @output.write(text) }
        else
          @output.write(text)
        end
        @output.flush if @output.respond_to?(:flush)
      end

      def encode_for_output(value)
        encoding = @output.external_encoding if @output.respond_to?(:external_encoding)
        return value unless encoding

        value.encode(encoding)
      rescue EncodingError, TypeError
        value.each_char.map do |character|
          begin
            character.encode(encoding)
          rescue EncodingError, TypeError
            character.bytesize == 1 ? format("\\x%02X", character.getbyte(0)) : format("\\u{%X}", character.ord)
          end
        end.join
      end

      def color_enabled?
        return false if ENV["NO_COLOR"] && !ENV["NO_COLOR"].empty?
        return false if defined?(RSpec) && RSpec.respond_to?(:configuration) &&
          RSpec.configuration.respond_to?(:color_mode) && RSpec.configuration.color_mode == :off

        @configuration.color
      end

      def style(value, color)
        return value unless color_enabled?
        return value unless color

        "#{COLORS.fetch(color)}#{value}#{RESET}"
      end

      def status_label(status)
        case status
        when :passed then [glyph("✅", "[PASS]") + " succeeded", :green]
        when :failed then [glyph("❌", "[FAIL]") + " failed", :red]
        when :pending then [glyph("⏸", "[PENDING]") + " pending", :yellow]
        when :skipped then [glyph("↪", "[SKIP]") + " skipped", :yellow]
        else [status.to_s, nil]
        end
      end

      def glyph(unicode, ascii)
        return ascii if @configuration.emoji == false
        return unicode if emoji_supported?(unicode)

        ascii
      end

      def emoji_supported?(value)
        return false unless @output.respond_to?(:external_encoding)
        encoding = @output.external_encoding
        return true unless encoding

        value.encode(encoding)
        true
      rescue EncodingError, TypeError
        false
      end

      def duration_suffix(run_time)
        threshold = @configuration.slow_threshold
        return "" if threshold.nil? || run_time.nil? || run_time < threshold

        "  #{format_seconds(run_time)}"
      end

      def format_seconds(value)
        seconds = value.to_f
        seconds < 1 ? format("%.0f ms", seconds * 1000) : format("%.2f s", seconds)
      end

      def format_milliseconds(value)
        format("%.1f ms", value.to_f * 1000)
      end

      class FailureColorizer
        def initialize(renderer)
          @renderer = renderer
        end

        def wrap(text, color)
          return text unless @renderer.formatter_color_enabled?

          code = COLORS[color]
          code ? "#{code}#{text}#{RESET}" : text
        end

        private

        COLORS = {
          red: "\e[31m",
          green: "\e[32m",
          yellow: "\e[33m",
          cyan: "\e[36m",
          bold: "\e[1m"
        }.freeze
      end

      def formatter_color_enabled?
        color_enabled?
      end
      public :formatter_color_enabled?
    end
  end
end
