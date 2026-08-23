# frozen_string_literal: true

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
        @bom_encoding = nil
        @converter = nil
        @converter_encoding = nil
        @encoding_carry = +""
        @escape_carry = +""
        @pending_cr = false
      end

      def process(value, encoding = nil)
        source = resolve_encoding(value, encoding)
        source_changed = @source_encoding && @source_encoding != source
        prefix = +""
        if source_changed
          prefix << parse("", final: true) if !@escape_carry.empty?
          prefix << flush_encoding_carry
          prefix << finish_converter
        end
        @bom_encoding = nil if source_changed
        @source_encoding = source

        bytes = @encoding_carry + value.to_s.b
        @encoding_carry = +""
        converted, @encoding_carry = decode(bytes, source)

        parse(prefix + converted)
      end

      def finish
        result = parse("", final: true)
        result << flush_encoding_carry
        result << finish_converter
        @escape_carry = +""
        @pending_cr = false
        @source_encoding = nil
        @bom_encoding = nil
        @converter = nil
        @converter_encoding = nil
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
        escape_bytes(carry)
      end

      def decode(bytes, source)
        return [binary_text(bytes), +""] if source == Encoding::BINARY
        return decode_utf8(bytes) if source == Encoding::UTF_8
        return decode_utf16(bytes) if source == Encoding::UTF_16
        return decode_utf8_variant(bytes, source) if source.name.start_with?("UTF8-")

        decode_with_converter(bytes, source)
      end

      def decode_utf8_variant(bytes, source)
        encoded = bytes.dup.force_encoding(source)
        return [encoded.encode(Encoding::UTF_8), +""] if encoded.valid_encoding?

        decode_utf8(bytes)
      rescue EncodingError
        decode_utf8(bytes)
      end

      def decode_utf16(bytes)
        unless @bom_encoding
          return ["", bytes] if bytes.bytesize < 2

          @bom_encoding = case bytes.byteslice(0, 2).bytes
          when [0xFE, 0xFF] then Encoding::UTF_16BE
          when [0xFF, 0xFE] then Encoding::UTF_16LE
          end
          return decode_with_converter(bytes, Encoding::UTF_16) unless @bom_encoding

          bytes = bytes.byteslice(2..).to_s.b
        end

        decode_with_converter(bytes, @bom_encoding)
      end

      def decode_utf8(bytes)
        encoded = bytes.dup.force_encoding(Encoding::UTF_8)
        return [encoded, +""] if encoded.valid_encoding?

        suffix_length = incomplete_utf8_suffix_length(bytes)
        if suffix_length.positive?
          prefix = bytes.byteslice(0, bytes.bytesize - suffix_length).to_s.force_encoding(Encoding::UTF_8)
          prefix = prefix.scrub { |invalid| escape_bytes(invalid.b) }
          return [prefix, bytes.byteslice(-suffix_length, suffix_length)]
        end

        [encoded.scrub { |invalid| escape_bytes(invalid.b) }, +""]
      end

      def incomplete_utf8_suffix_length(bytes)
        raw = bytes.bytes

        [3, raw.length].min.downto(1) do |length|
          suffix = raw.last(length)
          next unless utf8_incomplete_prefix?(suffix)

          return length
        end

        0
      end

      def utf8_incomplete_prefix?(bytes)
        leader = bytes.first
        expected = UTF8_LEADERS.find { |range, _| range.include?(leader) }&.last
        return false unless expected && bytes.length < expected
        return false unless bytes.drop(1).all? { |byte| byte.between?(0x80, 0xBF) }

        case leader
        when 0xE0
          bytes[1].nil? || bytes[1] >= 0xA0
        when 0xED
          bytes[1].nil? || bytes[1] <= 0x9F
        when 0xF0
          bytes[1].nil? || bytes[1] >= 0x90
        when 0xF4
          bytes[1].nil? || bytes[1] <= 0x8F
        else
          true
        end
      end

      def decode_with_converter(bytes, source)
        remaining = bytes.dup
        output = +"".b
        converter_for(source)

        loop do
          destination = +"".b
          result = @converter.primitive_convert(
            remaining, destination, nil, nil, Encoding::Converter::PARTIAL_INPUT
          )
          output << safe_utf8(destination)

          case result
          when :finished, :source_buffer_empty
            return [output.force_encoding(Encoding::UTF_8), +""]
          when :incomplete_input
            carry = @converter.primitive_errinfo[3].to_s.b
            return [output.force_encoding(Encoding::UTF_8), carry]
          when :invalid_byte_sequence
            error = @converter.primitive_errinfo
            invalid = error[3].to_s.b
            retry_bytes = error[4].to_s.b + remaining
            if invalid.empty?
              invalid = retry_bytes.byteslice(0, 1).to_s.b
              retry_bytes = retry_bytes.byteslice(1..).to_s.b
            end
            output << escape_bytes(invalid)
            return [output.force_encoding(Encoding::UTF_8), +""] if retry_bytes.empty?

            reset_converter
            converter_for(source)
            remaining = retry_bytes
          when :undefined_conversion
            error = @converter.primitive_errinfo
            invalid = error[3].to_s.b
            retry_bytes = error[4].to_s.b + remaining
            if invalid.empty?
              invalid = retry_bytes.byteslice(0, 1).to_s.b
              retry_bytes = retry_bytes.byteslice(1..).to_s.b
            end
            output << escape_bytes(invalid)
            return [output.force_encoding(Encoding::UTF_8), +""] if retry_bytes.empty?

            reset_converter
            converter_for(source)
            remaining = retry_bytes
          else
            return [output.force_encoding(Encoding::UTF_8), +""]
          end
        end
      rescue EncodingError, Encoding::ConverterNotFoundError
        [escape_bytes(bytes), +""]
      end

      def converter_for(source)
        return if @converter && @converter_encoding == source

        @converter = Encoding::Converter.new(source, Encoding::UTF_8)
        @converter_encoding = source
      end

      def reset_converter
        @converter = nil
        @converter_encoding = nil
      end

      def finish_converter
        return +"" unless @converter

        destination = +"".b
        empty = +"".b
        result = @converter.primitive_convert(empty, destination, nil, nil, 0)
        output = safe_utf8(destination)
        if result == :incomplete_input || result == :invalid_byte_sequence
          output << escape_bytes(@converter.primitive_errinfo[3].to_s.b)
        end
        reset_converter
        output
      rescue EncodingError
        reset_converter
        escape_bytes(@encoding_carry)
      end

      def safe_utf8(bytes)
        value = bytes.dup.force_encoding(Encoding::UTF_8)
        return value if value.valid_encoding?

        value.scrub { |invalid| escape_bytes(invalid.b) }
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

      def escape_bytes(bytes)
        bytes.bytes.map { |byte| format("\\x%02X", byte) }.join
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

            if sgr_sequence?(sequence)
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
        return ["\e", 1, false] if start + 1 >= input.bytesize

        second_byte = input.getbyte(start + 1)
        return ["\e", 1, true] if second_byte >= 0x80

        second = second_byte.chr
        if second == "["
          index = start + 2
          while index < input.bytesize && index - start <= MAX_ESCAPE_BYTES
            byte = input.getbyte(index)
            return [input.byteslice(start..index), index - start + 1, true] if byte.between?(0x40, 0x7E)
            if byte < 0x20 || byte == 0x7F || byte.between?(0x80, 0x9F)
              return [input.byteslice(start..index), index - start + 1, true]
            end
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

      def sgr_sequence?(sequence)
        bytes = sequence.bytes
        return false unless bytes.first(2) == [0x1B, 0x5B] && bytes.last == 0x6D

        bytes[2...-1].all? do |byte|
          byte.between?(0x30, 0x39) || byte == 0x3A || byte == 0x3B
        end
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
