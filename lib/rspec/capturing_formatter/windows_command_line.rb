# frozen_string_literal: true

module RSpec
  class CapturingFormatter
    # Produces arguments that survive cmd.exe passes and final Windows argv parsing.
    module WindowsCommandLine
      # Protect characters that cmd.exe interprets while parsing each layer.
      # Percent signs are doubled instead of caret-escaped because a caret does
      # not prevent percent expansion.
      CMD_META = "()[]%!^\"`<>&|;, *?\t"

      module_function

      # `cmd_layers` is the number of `cmd.exe` parsing passes the argument must
      # survive, in addition to the final Windows argv parsing.
      # Forwarding `%*` through a batch file adds a pass.
      def escape(value, cmd_layers: 1)
        value = value.to_s
        if value.match?(/[\0\r\n]/)
          raise ArgumentError, "Windows command arguments cannot contain NUL or newlines"
        end

        # Build Windows argv quoting before escaping each cmd.exe layer. A literal
        # quote needs 2n + 1 backslashes; a closing quote after n backslashes needs 2n.
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

      # The Windows RubyGems `rspec` batch launcher forwards `%*`, so rerun
      # arguments pass through two cmd.exe parsing layers.
      def rerun_argument(value)
        escape(value, cmd_layers: 2)
      end
    end
  end
end
