require "spec_helper"

RSpec.describe RSpec::CapturingFormatter::Configuration do
  subject(:configuration) { described_class.new }

  it "has the documented defaults" do
    expect(configuration.slow_threshold).to eq(0.5)
    expect(configuration.separator).to eq(" › ")
    expect(configuration.color).to be(true)
    expect(configuration.emoji).to eq(:auto)
    expect(configuration.pending_failure_output).to eq(:full)
  end

  it "validates settings" do
    expect { configuration.slow_threshold = -1 }.to raise_error(ArgumentError)
    expect { configuration.slow_threshold = Object.new }.to raise_error(ArgumentError)
    expect { configuration.separator = "" }.to raise_error(ArgumentError)
    expect { configuration.color = :yes }.to raise_error(ArgumentError)
    expect { configuration.emoji = :sometimes }.to raise_error(ArgumentError)
    expect { configuration.pending_failure_output = :sometimes }.to raise_error(ArgumentError)
  end

  it "accepts valid settings" do
    configuration.slow_threshold = nil
    configuration.separator = " / "
    configuration.color = false
    configuration.emoji = false
    configuration.pending_failure_output = :skip

    expect(configuration.to_h).to eq(
      slow_threshold: nil, separator: " / ", color: false, emoji: false,
      pending_failure_output: :skip
    )
  end
end
