# frozen_string_literal: true

require "monitor"

module RSpec
  class CapturingFormatter
    # Owns process-global stream capture and serializes captured writes with formatter callbacks.
    class CaptureManager
      # Older supported Rubies need keyword_init: true to construct leases from keyword arguments.
      # standard:disable Style/RedundantStructKeywordInit
      Lease = Struct.new(:manager, :owner, :generation, keyword_init: true) do
        # standard:enable Style/RedundantStructKeywordInit
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
        # Renderer writes can re-enter through a proxy, so capture synchronization must be reentrant.
        @monitor = Monitor.new
        @installed = false
        @active = false
        @pending_nonblock = {}
        @generation = 0
        @bypass_key = :rspec_capturing_formatter_bypass_depth
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
        existing = @monitor.synchronize { active_lease }
        return existing if existing

        install!
        @monitor.synchronize do
          existing = active_lease
          return existing if existing

          begin
            @formatter = formatter
            @active = true
            @generation += 1
            @stdout_proxy.activate!
            @stderr_proxy.activate!
            Lease.new(manager: self, owner: true, generation: @generation)
          # Activation mutates process-global capture state, so roll it back even outside StandardError.
          # standard:disable Lint/RescueException
          rescue Exception
            # standard:enable Lint/RescueException
            @active = false
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

      def generation
        @monitor.synchronize { @generation }
      end

      def synchronize(&block)
        @monitor.synchronize(&block)
      end

      def handle_write(proxy, value, method = :write, **options)
        @monitor.synchronize do
          pending = @pending_nonblock[proxy]
          if pending
            if nonblocking_method?(method) && pending != value
              raise Errno::EAGAIN
            end
            # This payload is already captured; remove its marker while a bypassed flush may re-enter here.
            @pending_nonblock.delete(proxy)
            begin
              @formatter.flush_pending
            rescue IO::WaitWritable, Errno::EAGAIN
              @pending_nonblock[proxy] = pending
              raise
            end
            return value.bytesize if nonblocking_method?(method) && pending == value
          end

          if !@active || bypassing? || proxy.raw_mode?
            proxy.write_backing(value, method, **options)
          else
            begin
              @formatter.capture(proxy.source, value, value.encoding)
            rescue IO::WaitWritable, Errno::EAGAIN
              @pending_nonblock[proxy] = value if nonblocking_method?(method)
              raise
            end
            value.bytesize
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
          return unless @active && lease.generation == @generation
          begin
            @formatter.finish_capture
          ensure
            @active = false
            @formatter = nil
            @pending_nonblock.clear
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
          @pending_nonblock.clear
          @stdout_proxy&.deactivate!
          @stderr_proxy&.deactivate!
          restore_globals
        end
      end

      def rollback_if_unchanged(expected_generation)
        @monitor.synchronize do
          return if @active || @generation != expected_generation

          restore_globals
        end
      end

      def uninstall!
        restore!
      end

      private

      def nonblocking_method?(method)
        method == :write_nonblock || method == :syswrite
      end

      def active_lease
        return unless @active

        raise "another RSpec::CapturingFormatter is already active"
      end

      def restore_globals
        # Do not overwrite a global stream that another component replaced while capture was active.
        $stdout = @original_stdout if @stdout_proxy && $stdout.equal?(@stdout_proxy)
        $stderr = @original_stderr if @stderr_proxy && $stderr.equal?(@stderr_proxy)
      end
    end

    # Presents an IO-like stream whose writes are captured or passed unchanged to its backing stream.
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
        @manager = other.manager
        # RSpec's any-process output matcher reopens from a clone and needs its current backing stream.
        @manager.synchronize do
          @backing = begin
            other.backing.dup
          rescue
            other.backing
          end
          @raw_mode = other.raw_mode?
          @closed = false
        end
      end

      def raw_mode?
        @raw_mode
      end

      attr_reader :manager

      attr_reader :backing

      def activate!
        @raw_mode = false
        @closed = false
      end

      def deactivate!
        @raw_mode = true
      end

      def write(value)
        string = String(value)
        @manager.handle_write(self, string, :write)
      end

      def write_nonblock(value, exception: true)
        string = String(value)
        @manager.handle_write(self, string, :write_nonblock, exception: exception)
      rescue IO::WaitWritable, Errno::EAGAIN
        raise if exception

        :wait_writable
      end

      def syswrite(value)
        string = String(value)
        @manager.handle_write(self, string, :syswrite)
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

      def put_value(value, ancestors = [])
        if value.is_a?(Array)
          if ancestors.include?(value.object_id)
            write("[...]\n")
          else
            value.each { |entry| put_value(entry, ancestors + [value.object_id]) }
          end
        else
          text = value.nil? ? "\n" : value.to_s
          newline = "\n".encode(text.encoding)
          write(text.end_with?(newline) ? text : text + newline)
        end
      end

      def print(*values)
        values = [$_] if values.empty? && defined?($_) && !$_.nil?
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
        character = value.is_a?(Integer) ? (value & 0xFF).chr(Encoding::BINARY) : value.to_s[0]
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
      alias_method :isatty, :tty?

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
        # Proxy targets restore matcher snapshots; other targets must bypass capture.
        @manager.synchronize do
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
        end
        self
      end

      def descriptor_backing?
        defined?(IO) && @backing.is_a?(IO)
      end

      def close
        @closed = true
        # A retained proxy can outlive capture; do not close a backing stream restored as a process global.
        @backing.close unless @backing.equal?($stdout) || @backing.equal?($stderr)
        nil
      end

      def write_backing(value, method = :write, **options)
        @manager.bypass { @backing.public_send(method, value, **options) }
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
