# frozen_string_literal: true

module RSpec
  class BetterFormatter
    module WindowsCommandLine
      CMD_META = "()[]%!^\"`<>&|;, *?\t"

      module_function

      def escape(value, cmd_layers: 1)
        value = value.to_s
        if value.match?(/[\0\r\n]/)
          raise ArgumentError, "Windows command arguments cannot contain NUL or newlines"
        end

        quoted = +'"'
        backslashes = 0
        value.each_char do |character|
          if character == "\\"
            backslashes += 1
          elsif character == '"'
            quoted << ("\\" * (backslashes * 2 + 1)) << '"'
            backslashes = 0
          else
            quoted << ("\\" * backslashes) << character
            backslashes = 0
          end
        end
        quoted << ("\\" * (backslashes * 2)) << '"'

        cmd_layers.times do
          quoted = quoted.each_char.map do |character|
            if character == "%"
              "%%"
            else
              CMD_META.include?(character) ? "^#{character}" : character
            end
          end.join
        end
        quoted
      end

      # RubyGems resolves `rspec` to a batch launcher on Windows. The launcher
      # forwards `%*`, which adds one command parsing layer.
      def rerun_argument(value)
        escape(value, cmd_layers: 2)
      end
    end
  end
end
