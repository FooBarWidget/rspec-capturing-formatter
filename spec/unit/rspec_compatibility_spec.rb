require "spec_helper"

RSpec.describe "RSpec pending failure compatibility" do
  it "provides the pending failure output setting on every supported RSpec version" do
    configuration = RSpec.configuration
    original = configuration.pending_failure_output

    configuration.pending_failure_output = :skip
    expect(configuration.pending_failure_output).to eq(:skip)
    expect { configuration.pending_failure_output = :invalid }.to raise_error(ArgumentError)
  ensure
    configuration.pending_failure_output = original if configuration && original
  end
end
