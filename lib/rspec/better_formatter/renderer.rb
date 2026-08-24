# frozen_string_literal: true

require "stringio"

module RSpec
  class BetterFormatter
    # Owns formatter report boundaries, captured-line state, styling, encoding fallbacks, and pending writes.
    class Renderer
      RESET = "\e[0m"
      COLORS = {
        green: "\e[32m",
        red: "\e[31m",
        yellow: "\e[33m",
        cyan: "\e[36m",
        gray: "\e[90m",
        bold: "\e[1m"
      }.freeze
      SOURCE_COLORS = {
        "stdout" => :gray,
        "stderr" => :yellow,
        "suite stdout" => :gray,
        "suite stderr" => :yellow
      }.freeze
      BOM_ENCODINGS = {
        "UTF-16" => "UTF-16BE",
        "UTF-32" => "UTF-32BE"
      }.freeze

      attr_reader :output

      def initialize(output, configuration, capture_manager: nil, ansi_supported: nil)
        @output = output || StringIO.new
        @configuration = configuration
        @capture_manager = capture_manager
        @ansi_supported = ansi_supported.nil? ? WindowsTerminal.ansi_supported?(@output) : ansi_supported
        @entry_started = false
        @entry_kind = nil
        @entry_path = nil
        @capture_source = nil
        @capture_open = false
        @capture_styled = false
        @sanitizers = {}
        @pending_output = nil
        @bom_output_encoding = nil
        @bom_written = false
      end

      def failure_colorizer
        FailureColorizer.new(self)
      end

      def example_started(path)
        finish_capture
        begin_entry
        @entry_kind = :example
        @entry_path = path
        line(path, :bold)
      end

      def context_started(path, heading: true)
        return if !heading && @entry_kind == :context && @entry_path == path

        finish_capture
        begin_entry
        @entry_kind = :context
        @entry_path = path
        line(path) if heading
      end

      def suite_started(heading: true)
        return if !heading && @entry_kind == :suite

        finish_capture
        begin_entry
        @entry_kind = :suite
        @entry_path = "RSpec suite"
        line("RSpec suite") if heading
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

      def pending(reason, location, skipped: false, run_time: nil)
        finish_capture
        label, color = status_label(skipped ? :skipped : :pending)
        line("  #{style(label, color)}#{duration_suffix(run_time)}")
        line("  reason | #{reason}") unless reason.to_s.empty?
        line("  rerun | #{location}") unless location.to_s.empty?
      end

      def rerun_inline(command)
        finish_capture
        line("  rerun | #{command}")
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
        examples = Array(examples)

        finish_capture
        begin_entry
        @entry_kind = :profile
        @entry_path = nil
        line("Profile")
        if notification.respond_to?(:slow_duration) && notification.respond_to?(:percentage)
          line("  Slowest examples total #{format_seconds(notification.slow_duration)} (#{notification.percentage}%)")
        end
        examples.each do |example|
          description = example.respond_to?(:full_description) ? example.full_description : example.to_s
          runtime = example.respond_to?(:execution_result) ? example.execution_result.run_time : nil
          location = example.location if example.respond_to?(:location)
          suffix = location.to_s.empty? ? "" : "  #{location}"
          line("  #{format_seconds(runtime)}  #{description}#{suffix}")
        end
        groups = notification.slowest_groups if notification.respond_to?(:slowest_groups)
        unless groups.nil? || groups.empty?
          line("  Slowest example groups")
          groups.each do |location, data|
            total = data[:total_time] if data.respond_to?(:[])
            count = data[:count] if data.respond_to?(:[])
            average = data[:average] if data.respond_to?(:[])
            description = data[:description] if data.respond_to?(:[])
            line("  #{description}") unless description.to_s.empty?
            line(
              "    #{format_seconds(total)} total  #{format_seconds(average)} average  " \
              "#{count} examples  #{location}"
            )
          end
        end
        line("  No examples profiled") if examples.empty? && (groups.nil? || groups.empty?)
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

      def flush_pending
        flush_pending_output
      end

      private

      def emit_captured_text(source, text)
        text = strip_sgr(text) unless @ansi_supported
        return if text.empty?

        @capture_styled = true if text.match?(/\e\[[0-?]*[ -\/]*m/)

        begin_entry unless @entry_started
        prefix = style("  #{source} | ", SOURCE_COLORS[source])
        rendered = +""
        unless @capture_open
          rendered << RESET if color_enabled?
          rendered << prefix
        end

        parts = text.split("\n", -1)
        parts.each_with_index do |part, index|
          rendered << captured_part(source, part)
          next unless index < parts.length - 1

          rendered << RESET if color_enabled?
          rendered << "\n"
          rendered << prefix unless index == parts.length - 2 && parts.last.empty?
        end

        @capture_open = true unless text.end_with?("\n")
        @capture_open = false if text.end_with?("\n")
        write_raw(rendered)
      end

      def captured_part(source, value)
        return value if value.empty? || @capture_styled

        style(value, SOURCE_COLORS[source])
      end

      def begin_entry
        finish_capture
        write_raw("\n") if @entry_started
        @entry_started = true
      end

      def line(value, color = nil)
        value = value.to_s
        value = strip_sgr(value) unless @ansi_supported
        write_raw(RESET) if color_enabled?
        write_raw(style(value, color))
        write_raw("\n")
      end

      def write_raw(value)
        return if value.nil? || value.empty?

        text = encode_for_output(value)
        if @pending_output.nil? || @pending_output.empty?
          @pending_output = text.dup
        else
          @pending_output << text
        end
        flush_pending_output
      end

      def flush_pending_output
        while @pending_output && !@pending_output.empty?
          written = if @capture_manager
            @capture_manager.bypass { write_pending_chunk }
          elsif defined?(CaptureManager)
            CaptureManager.instance.bypass { write_pending_chunk }
          else
            write_pending_chunk
          end
          written = @pending_output.bytesize if written.nil?
          remaining = @pending_output.byteslice(written..)
          @pending_output = remaining && !remaining.empty? ? remaining : nil
        end
        @output.flush if @output.respond_to?(:flush)
      end

      def write_pending_chunk
        begin
          if @output.respond_to?(:write_nonblock)
            written = @output.write_nonblock(@pending_output)
            raise Errno::EAGAIN if written == :wait_writable

            written
          else
            @output.write(@pending_output)
          end
        rescue EncodingError, ArgumentError
          raise if @pending_output.ascii_only?

          @pending_output = ascii_fallback(@pending_output)
          retry
        end
      rescue IO::WaitWritable, Errno::EAGAIN
        raise
      end

      def encode_for_output(value)
        requested = @output.external_encoding if @output.respond_to?(:external_encoding)
        return value unless requested

        encoding = BOM_ENCODINGS.fetch(requested.name, requested.name)
        activate_bom_destination(encoding) if BOM_ENCODINGS.key?(requested.name)
        encoded = begin
          value.encode(encoding)
        rescue EncodingError, TypeError
          fallback = value.each_char.map do |character|
            begin
              character.encode(encoding).encode(Encoding::UTF_8)
            rescue EncodingError, TypeError
              character.bytesize == 1 ? format("\\x%02X", character.getbyte(0)) : format("\\u{%X}", character.ord)
            end
          end.join
          fallback.encode(encoding)
        end

        if @bom_output_encoding && !@bom_written
          @bom_written = true
          "\uFEFF".encode(@bom_output_encoding) + encoded
        else
          encoded
        end
      end

      def activate_bom_destination(encoding)
        return if @bom_output_encoding

        @bom_output_encoding = encoding
        @output.set_encoding(encoding) if @output.respond_to?(:set_encoding)
      rescue EncodingError, TypeError
        @bom_output_encoding = encoding
      end

      def ascii_fallback(value)
        value.bytes.map do |byte|
          byte == 9 || byte == 10 || byte == 13 || byte.between?(0x20, 0x7E) ? byte.chr : format("\\x%02X", byte)
        end.join
      end

      def color_enabled?
        return false unless @ansi_supported
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

      def strip_sgr(value)
        value.gsub(/\e\[[0-?]*[ -\/]*m/, "")
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
