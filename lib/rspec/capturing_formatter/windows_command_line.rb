# frozen_string_literal: true

module RSpec
  class CapturingFormatter
    # Builds rerun commands without exposing dynamic targets to cmd.exe parsing.
    module WindowsCommandLine
      DECODE_ARGUMENT = 'ARGV[0]=ARGV.fetch(0).unpack1("m0").force_encoding("UTF-8")'
      RUN_RSPEC = 'load(Gem.bin_path("rspec-core","rspec"))'

      # Protect characters that cmd.exe interprets while parsing a pasted command.
      CMD_META = "()[]^\"`<>&|;, *?\t"

      module_function

      def rerun_command(value)
        encoded_ruby_command(RUN_RSPEC, value)
      end

      # Dynamic values are encoded because cmd.exe expands paired percent signs
      # and exclamation marks before an executable can receive them.
      def encoded_ruby_command(script, value)
        value = valid_value(value).encode(Encoding::UTF_8)
        bootstrap = "#{DECODE_ARGUMENT};#{script}"
        "ruby -e #{escape(bootstrap)} #{[value].pack("m0")}"
      end

      def escape(value)
        value = valid_value(value)
        if value.match?(/[%!]/)
          raise ArgumentError, "dynamic cmd.exe arguments containing percent signs or exclamation marks must be encoded"
        end

        # Build Windows argv quoting before escaping the cmd.exe layer. A literal
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

        quoted.each_char.map do |character|
          CMD_META.include?(character) ? "^#{character}" : character
        end.join
      end

      def valid_value(value)
        value = value.to_s
        if value.match?(/[\0\r\n]/)
          raise ArgumentError, "Windows command arguments cannot contain NUL or newlines"
        end
        value
      end
      private_class_method :valid_value
    end
  end
end
