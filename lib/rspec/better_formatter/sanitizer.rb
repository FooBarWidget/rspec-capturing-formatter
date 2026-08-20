module RSpec
  class BetterFormatter
    # Converts terminal-affecting application output into safe report text.
    class Sanitizer
      MAX_ESCAPE_BYTES = 128
      UTF8_LEADERS = {
        (0xC2..0xDF) => 2,
        (0xE0..0xEF) => 3,
        (0xF0..0xF4) => 4
      }.freeze

      def initialize
        @source_encoding = nil
        @encoding_carry = +""
        @escape_carry = +""
        @pending_cr = false
      end

      def process(value, encoding = nil)
        source = resolve_encoding(value, encoding)
        source_changed = @source_encoding && @source_encoding != source
        prefix = source_changed ? flush_encoding_carry : +""
        if source_changed && !@escape_carry.empty?
          prefix << parse("", final: true)
        end
        @source_encoding = source
        bytes = @encoding_carry + value.to_s.b
        @encoding_carry = +""

        if source == Encoding::BINARY
          converted = binary_text(bytes)
        else
          bytes, @encoding_carry = retain_incomplete_character(bytes, source)
          converted = transcode(bytes, source)
        end

        parse(prefix + converted)
      end

      def finish
        result = flush_encoding_carry
        result << parse("", final: true)
        @escape_carry = +""
        result
      end

      private

      def resolve_encoding(value, encoding)
        return Encoding.find(encoding.to_s) if encoding

        value.respond_to?(:encoding) ? value.encoding : Encoding::UTF_8
      rescue ArgumentError
        Encoding::UTF_8
      end

      def flush_encoding_carry
        return +"" if @encoding_carry.empty?

        carry = @encoding_carry
        @encoding_carry = +""
        if @source_encoding == Encoding::BINARY
          binary_text(carry)
        else
          transcode(carry, @source_encoding)
        end
      end

      def retain_incomplete_character(bytes, source)
        return [bytes, +""] if bytes.empty?

        encoded = bytes.dup.force_encoding(source)
        return [bytes, +""] if encoded.valid_encoding?

        if source == Encoding::UTF_8
          suffix_length = incomplete_utf8_suffix_length(bytes)
          if suffix_length.positive?
            return [bytes.byteslice(0, bytes.bytesize - suffix_length),
                    bytes.byteslice(-suffix_length, suffix_length)]
          end
        elsif source == Encoding::UTF_16LE || source == Encoding::UTF_16BE
          if bytes.bytesize.odd?
            return [bytes.byteslice(0, bytes.bytesize - 1), bytes.byteslice(-1, 1)]
          end
        end

        [bytes, +""]
      end

      def incomplete_utf8_suffix_length(bytes)
        raw = bytes.bytes
        index = raw.length - 1
        continuation_count = 0
        while index >= 0 && raw[index].between?(0x80, 0xBF)
          continuation_count += 1
          index -= 1
        end

        leader = raw[index]
        expected = UTF8_LEADERS.find { |range, _| range.include?(leader) }&.last
        return 0 unless expected
        return 0 if continuation_count >= expected - 1

        suffix_length = continuation_count + 1
        suffix_length == raw.length ? suffix_length : 0
      end

      def transcode(bytes, source)
        return +"" if bytes.empty?

        value = bytes.dup.force_encoding(source)
        value = value.scrub { |invalid| invalid.bytes.map { |byte| format("\\x%02X", byte) }.join }
        value.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        binary_text(bytes)
      end

      def binary_text(bytes)
        bytes.bytes.map do |byte|
          if byte == 9 || byte == 10 || byte == 13 || byte.between?(0x20, 0x7E)
            byte.chr
          else
            format("\\x%02X", byte)
          end
        end.join
      end

      def parse(text, final: false)
        input = @escape_carry + text.to_s
        @escape_carry = +""
        output = +""
        index = 0

        while index < input.bytesize
          if @pending_cr
            @pending_cr = false if input.getbyte(index) != 10
            if input.getbyte(index) == 10
              index += 1
              next
            end
          end

          if input.getbyte(index) == 0x1B
            sequence, consumed, complete = terminal_sequence(input, index)
            unless complete
              if !final && input.bytesize - index <= MAX_ESCAPE_BYTES
                @escape_carry = input.byteslice(index..)
                break
              end

              output << visible_escape(input.byteslice(index..))
              break
            end

            if sequence.end_with?("m") && sequence.start_with?("\e[")
              output << sequence
            else
              output << visible_escape(sequence)
            end
            index += consumed
            next
          end

          character = input.byteslice(index..).each_char.first
          character_bytes = character.bytesize
          case character
          when "\r"
            output << "\n"
            @pending_cr = true
          when "\n", "\t"
            output << character
          else
            codepoint = character.ord
            if codepoint < 0x20 || codepoint == 0x7F || codepoint.between?(0x80, 0x9F)
              output << format("\\x%02X", codepoint)
            else
              output << character
            end
          end
          index += character_bytes
        end

        output
      end

      def terminal_sequence(input, start)
        return ["\e", 1, true] if start + 1 >= input.bytesize

        second = input.byteslice(start + 1, 1)
        if second == "["
          index = start + 2
          while index < input.bytesize && index - start <= MAX_ESCAPE_BYTES
            byte = input.getbyte(index)
            return [input.byteslice(start..index), index - start + 1, true] if byte.between?(0x40, 0x7E)
            index += 1
          end
          return [input.byteslice(start..), input.bytesize - start, false]
        end

        if second == "]"
          index = start + 2
          while index < input.bytesize && index - start <= MAX_ESCAPE_BYTES
            return [input.byteslice(start..index), index - start + 1, true] if input.getbyte(index) == 7
            if input.getbyte(index) == 0x1B && input.getbyte(index + 1) == 92
              return [input.byteslice(start..index + 1), index - start + 2, true]
            end
            index += 1
          end
          return [input.byteslice(start..), input.bytesize - start, false]
        end

        [input.byteslice(start, 2), 2, true]
      end

      def visible_escape(sequence)
        sequence.to_s.bytes.map do |byte|
          case byte
          when 0x1B then "\\e"
          when 0x20..0x7E then byte.chr
          else format("\\x%02X", byte)
          end
        end.join
      end
    end
  end
end
