require "spec_helper"
require "stringio"

RSpec.describe RSpec::BetterFormatter::Renderer do
  let(:output) { StringIO.new }
  let(:configuration) do
    RSpec::BetterFormatter::Configuration.new.tap do |value|
      value.color = false
      value.emoji = false
    end
  end
  subject(:renderer) { described_class.new(output, configuration) }

  it "keeps formatter entries append-only with one blank line between them" do
    renderer.example_started("A car › it is red")
    renderer.result(:passed, 0.01)
    renderer.context_started("A car › during maintenance")
    renderer.capture("suite stdout", "preparing\n")

    expect(output.string).to eq(
      "A car › it is red\n  [PASS] succeeded\n\n" \
      "A car › during maintenance\n  suite stdout | preparing\n"
    )
  end

  it "flushes partial lines and labels each physical line" do
    renderer.example_started("A car › it beeps")
    renderer.capture("stdout", "starting")
    renderer.capture("stdout", " engine\nnext\n")
    renderer.capture("stderr", "warning")
    renderer.result(:passed, 0.01)

    expect(output.string).to include("  stdout | starting engine\n  stdout | next\n")
    expect(output.string).to include("  stderr | warning\n  [PASS] succeeded\n")
  end

  it "resets captured application styling before formatter output" do
    renderer.example_started("A car › it is red")
    renderer.capture("stdout", "\e[31mred")
    renderer.result(:passed, 0.01)

    expect(output.string).to include("stdout | \e[31mred\e[0m\n")
    expect(output.string).to include("  [PASS] succeeded\n")
  end

  it "keeps RSpec messages inside the active example entry" do
    renderer.example_started("A car › it reports")
    renderer.capture("stdout", "partial")
    renderer.message("Failure/Error: diagnostic\nRuntimeError: broken", inside_example: true)
    renderer.capture("stdout", "continued\n")
    renderer.result(:failed, 0.01)

    expect(output.string).to include("stdout | partial\n  rspec | Failure/Error: diagnostic\n")
    expect(output.string).to include("  rspec | RuntimeError: broken\n  stdout | continued\n")
  end
end
