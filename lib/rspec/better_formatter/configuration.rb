module RSpec
  class BetterFormatter
    class Configuration
      attr_reader :slow_threshold, :separator, :color, :emoji

      def initialize
        @slow_threshold = 0.5
        @separator = " › "
        @color = true
        @emoji = :auto
      end

      def slow_threshold=(value)
        unless value.nil? || (value.is_a?(Numeric) && value >= 0)
          raise ArgumentError, "slow_threshold must be a non-negative number or nil"
        end

        @slow_threshold = value
      end

      def separator=(value)
        unless value.is_a?(String) && !value.empty?
          raise ArgumentError, "separator must be a non-empty string"
        end

        @separator = value
      end

      def color=(value)
        unless value == true || value == false
          raise ArgumentError, "color must be true or false"
        end

        @color = value
      end

      def emoji=(value)
        unless [:auto, true, false].include?(value)
          raise ArgumentError, "emoji must be :auto, true, or false"
        end

        @emoji = value
      end

      def to_h
        {
          slow_threshold: @slow_threshold,
          separator: @separator,
          color: @color,
          emoji: @emoji
        }
      end
    end
  end
end
