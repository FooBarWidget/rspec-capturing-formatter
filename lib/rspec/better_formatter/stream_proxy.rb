require "monitor"

module RSpec
  class BetterFormatter
    class CaptureManager
      Lease = Struct.new(:manager, :owner, keyword_init: true) do
        def owner?
          owner
        end
      end

      class << self
        def instance
          @instance ||= new
        end

        def install!
          instance.install!
        end
      end

      attr_reader :stdout_proxy, :stderr_proxy

      def initialize
        @monitor = Monitor.new
        @installed = false
        @active = false
        @bypass_key = :rspec_better_formatter_bypass_depth
      end

      def install!
        @monitor.synchronize do
          return self if @installed && $stdout.equal?(@stdout_proxy) && $stderr.equal?(@stderr_proxy)

          @original_stdout ||= $stdout
          @original_stderr ||= $stderr
          @stdout_proxy ||= StreamProxy.new(@original_stdout, :stdout, self)
          @stderr_proxy ||= StreamProxy.new(@original_stderr, :stderr, self)
          $stdout = @stdout_proxy
          $stderr = @stderr_proxy
          @installed = true
        end
        self
      end

      def activate(output, formatter)
        existing = @monitor.synchronize { active_lease(output) }
        return existing if existing

        install!
        @monitor.synchronize do
          existing = active_lease(output)
          return existing if existing

          begin
            @output = output
            @formatter = formatter
            @active = true
            @stdout_proxy.activate!
            @stderr_proxy.activate!
            Lease.new(manager: self, owner: true)
          rescue Exception
            @active = false
            @output = nil
            @formatter = nil
            @stdout_proxy.deactivate!
            @stderr_proxy.deactivate!
            restore_globals
            raise
          end
        end
      end

      def active?
        @monitor.synchronize { @active }
      end

      def handle_write(proxy, value)
        @monitor.synchronize do
          if !@active || bypassing? || proxy.raw_mode?
            proxy.write_backing(value)
          else
            @formatter.capture(proxy.source, value, value.encoding)
          end
        end
      end

      def bypass
        depth = Thread.current[@bypass_key].to_i
        Thread.current[@bypass_key] = depth + 1
        yield
      ensure
        Thread.current[@bypass_key] = depth
      end

      def bypassing?
        Thread.current[@bypass_key].to_i.positive?
      end

      def deactivate(lease)
        return unless lease&.owner?
        return unless lease.manager.equal?(self)

        @monitor.synchronize do
          return unless @active
          begin
            @formatter.finish_capture
          ensure
            @active = false
            @formatter = nil
            @output = nil
            @stdout_proxy.deactivate!
            @stderr_proxy.deactivate!
            restore_globals
          end
        end
      end

      def restore!
        @monitor.synchronize do
          @active = false
          @formatter = nil
          @output = nil
          @stdout_proxy&.deactivate!
          @stderr_proxy&.deactivate!
          restore_globals
        end
      end

      def uninstall!
        restore!
      end

      private

      def active_lease(output)
        return unless @active
        return Lease.new(manager: self, owner: false) if @output.equal?(output)

        raise "another RSpec::BetterFormatter is already active"
      end

      def restore_globals
        $stdout = @original_stdout if @stdout_proxy && $stdout.equal?(@stdout_proxy)
        $stderr = @original_stderr if @stderr_proxy && $stderr.equal?(@stderr_proxy)
      end
    end

    class StreamProxy
      attr_reader :source

      def initialize(backing, source, manager)
        @backing = backing
        @source = source
        @manager = manager
        @raw_mode = false
        @closed = false
      end

      def initialize_copy(other)
        super
        @backing = begin
          other.backing.dup
        rescue StandardError
          other.backing
        end
        @manager = other.manager
        @raw_mode = other.raw_mode?
        @closed = false
      end

      def raw_mode?
        @raw_mode
      end

      def manager
        @manager
      end

      def backing
        @backing
      end

      def activate!
        @raw_mode = false
        @closed = false
      end

      def deactivate!
        @raw_mode = true
      end

      def write(value)
        string = String(value)
        @manager.handle_write(self, string)
        string.bytesize
      end

      def write_nonblock(value, exception: true)
        write(value)
      rescue IO::WaitWritable
        raise if exception
        :wait_writable
      end

      def syswrite(value)
        write(value)
      end

      def <<(value)
        write(value)
        self
      end

      def puts(*values)
        values = [nil] if values.empty?
        values.each { |value| put_value(value) }
        nil
      end

      def put_value(value)
        if value.is_a?(Array)
          value.each { |entry| put_value(entry) }
        else
          text = value.nil? ? "\n" : value.to_s
          write(text)
          write("\n") unless text.end_with?("\n")
        end
      end

      def print(*values)
        separator = $OUTPUT_FIELD_SEPARATOR
        terminator = $OUTPUT_RECORD_SEPARATOR
        values.each_with_index do |value, index|
          write(separator) if index.positive? && separator
          write(value)
        end
        write(terminator) if values.any? && terminator
        nil
      end

      def printf(format_string, *values)
        write(format_string % values)
        nil
      end

      def putc(value)
        character = value.is_a?(Integer) ? value.chr : value.to_s[0]
        write(character)
        value
      end

      def flush
        @manager.bypass { @backing.flush } if @backing.respond_to?(:flush)
        self
      end

      def sync
        @backing.sync if @backing.respond_to?(:sync)
      end

      def sync=(value)
        @backing.sync = value if @backing.respond_to?(:sync=)
      end

      def tty?
        @backing.respond_to?(:tty?) && @backing.tty?
      end
      alias isatty tty?

      def closed?
        @closed || (@backing.respond_to?(:closed?) && @backing.closed?)
      end

      def external_encoding
        @backing.respond_to?(:external_encoding) ? @backing.external_encoding : Encoding::UTF_8
      end

      def internal_encoding
        @backing.respond_to?(:internal_encoding) ? @backing.internal_encoding : nil
      end

      def set_encoding(*arguments)
        @backing.set_encoding(*arguments) if @backing.respond_to?(:set_encoding)
        self
      end

      def binmode
        @backing.binmode if @backing.respond_to?(:binmode)
        self
      end

      def fileno
        @backing.fileno
      end

      def to_io
        self
      end

      def reopen(target, *arguments)
        if target.is_a?(StreamProxy)
          if descriptor_backing?
            @backing.reopen(target.backing)
          else
            @backing = target.backing
          end
          @raw_mode = target.raw_mode?
        elsif descriptor_backing? && (target.respond_to?(:read) || target.respond_to?(:write))
          @backing.reopen(target.respond_to?(:to_io) ? target.to_io : target, *arguments)
          @raw_mode = true
        elsif target.respond_to?(:read) || target.respond_to?(:write)
          @backing = target
          @raw_mode = true
        elsif @backing.respond_to?(:reopen)
          @backing.reopen(target, *arguments)
          @raw_mode = true
        else
          @backing = target
          @raw_mode = true
        end
        self
      end

      def descriptor_backing?
        defined?(IO) && @backing.is_a?(IO)
      end

      def close
        @closed = true
        @backing.close unless @backing.equal?($stdout) || @backing.equal?($stderr)
        nil
      end

      def write_backing(value)
        @manager.bypass { @backing.write(value) }
      end

      def method_missing(name, *arguments, &block)
        return super unless @backing.respond_to?(name)

        @backing.public_send(name, *arguments, &block)
      end

      def respond_to_missing?(name, include_private = false)
        @backing.respond_to?(name, include_private) || super
      end
    end
  end
end
