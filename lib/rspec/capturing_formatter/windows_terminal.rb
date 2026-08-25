# frozen_string_literal: true

require "fiddle" if Gem.win_platform?

module RSpec
  class CapturingFormatter
    # Determines ANSI support and enables Virtual Terminal processing for Windows Terminal output.
    module WindowsTerminal
      ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
      STD_OUTPUT_HANDLE = -11
      STD_ERROR_HANDLE = -12

      class << self
        # Redirected output remains ANSI-capable; interactive output requires Windows Terminal and VT support.
        # Fiddle failures fall back to plain text, while unrelated errors propagate.
        def ansi_supported?(output, platform: Gem.win_platform?, env: ENV, api: nil)
          return true unless platform

          begin
            return true unless tty?(output)
            return false unless windows_terminal?(env)

            (api || NativeApi.new).enable_virtual_terminal_processing(output)
          rescue Fiddle::Error
            false
          end
        end

        private

        def tty?(output)
          output.respond_to?(:tty?) && output.tty?
        end

        def windows_terminal?(env)
          value = env["WT_SESSION"]
          value && !value.empty?
        end
      end

      # Isolates the Fiddle bindings for the Windows console API.
      class NativeApi
        def initialize
          kernel32 = Fiddle.dlopen("kernel32.dll")
          @get_std_handle = function(kernel32, "GetStdHandle", [Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP)
          @get_console_mode = function(
            kernel32,
            "GetConsoleMode",
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @set_console_mode = function(
            kernel32,
            "SetConsoleMode",
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG],
            Fiddle::TYPE_INT
          )
        end

        def enable_virtual_terminal_processing(output)
          handle = @get_std_handle.call(std_handle(output))
          return false if handle.to_i.zero? || handle.to_i == -1

          # Console modes are Windows DWORDs: four little-endian bytes.
          mode = Fiddle::Pointer.malloc(4)
          return false if @get_console_mode.call(handle, mode).zero?

          current_mode = mode[0, 4].unpack1("V")
          return true if (current_mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING).positive?

          !@set_console_mode.call(handle, current_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING).zero?
        end

        private

        def function(library, name, arguments, result)
          Fiddle::Function.new(library[name], arguments, result)
        end

        def std_handle(output)
          source = output.source if output.respond_to?(:source)
          (source == :stderr) ? STD_ERROR_HANDLE : STD_OUTPUT_HANDLE
        end
      end
    end
  end
end
