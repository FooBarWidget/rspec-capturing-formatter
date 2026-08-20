require "spec_helper"

RSpec.describe RSpec::BetterFormatter::Configuration do
  subject(:configuration) { described_class.new }

  it "has the documented defaults" do
    expect(configuration.slow_threshold).to eq(0.5)
    expect(configuration.separator).to eq(" › ")
    expect(configuration.color).to be(true)
    expect(configuration.emoji).to eq(:auto)
  end

  it "validates settings" do
    expect { configuration.slow_threshold = -1 }.to raise_error(ArgumentError)
    expect { configuration.slow_threshold = Object.new }.to raise_error(ArgumentError)
    expect { configuration.separator = "" }.to raise_error(ArgumentError)
    expect { configuration.color = :yes }.to raise_error(ArgumentError)
    expect { configuration.emoji = :sometimes }.to raise_error(ArgumentError)
  end

  it "accepts valid settings" do
    configuration.slow_threshold = nil
    configuration.separator = " / "
    configuration.color = false
    configuration.emoji = false

    expect(configuration.to_h).to eq(
      slow_threshold: nil, separator: " / ", color: false, emoji: false
    )
  end
end
