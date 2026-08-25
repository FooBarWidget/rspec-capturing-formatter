# frozen_string_literal: true

module RSpec
  class CapturingFormatter
    class Configuration
      attr_reader :slow_threshold, :separator, :color, :emoji

      def initialize
        @slow_threshold = 0.5
        @separator = " › "
        @color = true
        @emoji = :auto
        @pending_failure_output = nil
      end

      def slow_threshold=(value)
        valid = value.nil? || (value.is_a?(Numeric) && value >= 0)
        unless valid
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

      # Keep "unset" distinct from explicit :full so CapturingFormatter can inherit RSpec's setting.
      def pending_failure_output=(value)
        unless [:full, :no_backtrace, :skip].include?(value)
          raise ArgumentError, "pending_failure_output must be :full, :no_backtrace, or :skip"
        end

        @pending_failure_output = value
      end

      def pending_failure_output
        @pending_failure_output || :full
      end

      def pending_failure_output_configured?
        !@pending_failure_output.nil?
      end

      def to_h
        {
          slow_threshold: @slow_threshold,
          separator: @separator,
          color: @color,
          emoji: @emoji,
          pending_failure_output: pending_failure_output
        }
      end
    end
  end
end
