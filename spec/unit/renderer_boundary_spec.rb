require "spec_helper"
require "stringio"

RSpec.describe RSpec::BetterFormatter::Renderer do
  it "flushes sanitizer carries at entry boundaries" do
    output = StringIO.new
    configuration = RSpec::BetterFormatter::Configuration.new.tap do |value|
      value.color = false
      value.emoji = false
    end
    renderer = described_class.new(output, configuration)

    renderer.example_started("A car › it logs")
    renderer.capture("stdout", "ok\n\e[")
    renderer.result(:passed, 0.01)

    expect(output.string).to include("  stdout | ok\n  stdout | \\e[\n  [PASS] succeeded\n")
  end
end
