require "spec_helper"

RSpec.describe RSpec::BetterFormatter do
  ExampleResult = Struct.new(:run_time)
  Example = Struct.new(:execution_result)
  Notification = Struct.new(:example)

  class BlockingOutput
    attr_reader :entered

    def initialize
      @io = +""
      @entered = Queue.new
      @release = Queue.new
    end

    def external_encoding
      Encoding::UTF_8
    end

    def write(value)
      if value.start_with?("  stdout | ")
        @entered << true
        @release.pop
      end
      @io << value
      value.bytesize
    end

    def flush
      self
    end

    def release
      @release << true
    end

    def string
      @io
    end
  end

  class EagainOutput
    def initialize
      @value = +""
      @fail_once = true
    end

    def external_encoding
      Encoding::UTF_8
    end

    def write(value)
      if @fail_once
        @fail_once = false
        raise Errno::EAGAIN
      end
      @value << value
      value.bytesize
    end

    def flush
      self
    end

    def string
      @value
    end
  end

  class PartialEagainOutput
    def initialize
      @value = +""
      @state = :partial
    end

    def external_encoding
      Encoding::UTF_8
    end

    def write_nonblock(value, exception: true)
      if @state == :partial
        @state = :wait
        @value << value.byteslice(0, 5)
        return 5
      elsif @state == :wait
        @state = :done
        return :wait_writable
      end
      @value << value
      value.bytesize
    end

    def flush
      self
    end

    def string
      @value
    end
  end

  it "does not let a result split a captured prefix from its payload" do
    configuration = described_class.configuration
    previous_color = configuration.color
    previous_emoji = configuration.emoji
    configuration.color = false
    configuration.emoji = false
    output = BlockingOutput.new
    manager = RSpec::BetterFormatter::CaptureManager.new
    formatter = described_class.new(output, capture_manager: manager)
    example = Example.new(ExampleResult.new(0.01))
    notification = Notification.new(example)
    formatter.instance_variable_set(:@current_example, example)

    writer = Thread.new { formatter.capture(:stdout, "payload", Encoding::UTF_8) }
    output.entered.pop
    callback_started = Queue.new
    callback = Thread.new do
      callback_started << true
      formatter.example_passed(notification)
    end
    callback_started.pop
    sleep 0.01

    expect(output.string).not_to include("succeeded")

    output.release
    writer.join
    callback.join
    expect(output.string).to include("  stdout | payload\n  [PASS] succeeded\n")
  ensure
    output&.release
    writer&.join
    callback&.join
    formatter&.close
    configuration.color = previous_color if configuration && previous_color
    configuration.emoji = previous_emoji if configuration && previous_emoji
  end

  it "retains a captured nonblocking payload across EAGAIN" do
    configuration = described_class.configuration
    previous_color = configuration.color
    previous_emoji = configuration.emoji
    configuration.color = false
    configuration.emoji = false
    output = EagainOutput.new
    manager = RSpec::BetterFormatter::CaptureManager.new
    formatter = described_class.new(output, capture_manager: manager)
    example = Example.new(ExampleResult.new(0.01))
    formatter.instance_variable_set(:@current_example, example)

    expect($stdout.write_nonblock("payload", exception: false)).to eq(:wait_writable)
    expect($stdout.write_nonblock("payload", exception: false)).to eq(7)
    expect(output.string.scan("payload").length).to eq(1)
  ensure
    formatter&.close
    configuration.color = previous_color if configuration && previous_color
    configuration.emoji = previous_emoji if configuration && previous_emoji
  end

  it "retains a captured syswrite payload across EAGAIN" do
    configuration = described_class.configuration
    previous_color = configuration.color
    previous_emoji = configuration.emoji
    configuration.color = false
    configuration.emoji = false
    output = EagainOutput.new
    manager = RSpec::BetterFormatter::CaptureManager.new
    formatter = described_class.new(output, capture_manager: manager)
    example = Example.new(ExampleResult.new(0.01))
    formatter.instance_variable_set(:@current_example, example)

    expect { $stdout.syswrite("payload") }.to raise_error(Errno::EAGAIN)
    expect($stdout.syswrite("payload")).to eq(7)
    expect(output.string.scan("payload").length).to eq(1)
  ensure
    formatter&.close
    configuration.color = previous_color if configuration && previous_color
    configuration.emoji = previous_emoji if configuration && previous_emoji
  end

  it "does not duplicate bytes already written before EAGAIN" do
    configuration = described_class.configuration
    previous_color = configuration.color
    previous_emoji = configuration.emoji
    configuration.color = false
    configuration.emoji = false
    output = PartialEagainOutput.new
    manager = RSpec::BetterFormatter::CaptureManager.new
    formatter = described_class.new(output, capture_manager: manager)
    example = Example.new(ExampleResult.new(0.01))
    formatter.instance_variable_set(:@current_example, example)

    expect($stdout.write_nonblock("payload", exception: false)).to eq(:wait_writable)
    expect($stdout.write_nonblock("payload", exception: false)).to eq(7)
    expect(output.string.scan("payload").length).to eq(1)
  ensure
    formatter&.close
    configuration.color = previous_color if configuration && previous_color
    configuration.emoji = previous_emoji if configuration && previous_emoji
  end
end
