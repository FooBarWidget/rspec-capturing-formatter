require "spec_helper"

RSpec.describe RSpec::BetterFormatter::Renderer do
  class AsciiOnlyOutput
    attr_reader :value

    def initialize
      @value = +""
    end

    def write(value)
      raise EncodingError unless value.ascii_only?

      @value << value
      value.bytesize
    end

    def flush
      self
    end
  end

  it "falls back to visible byte escapes for writers without encoding metadata" do
    output = AsciiOnlyOutput.new
    configuration = RSpec::BetterFormatter::Configuration.new.tap do |value|
      value.color = false
      value.emoji = false
    end
    renderer = described_class.new(output, configuration)

    renderer.example_started("A car › it is red")
    renderer.result(:passed, 0.01)

    expect(output.value).to include("\\xE2\\x80\\xBA")
    expect(output.value).to include("[PASS] succeeded")
  end
end
