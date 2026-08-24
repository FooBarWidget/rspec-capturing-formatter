RSpec::CapturingFormatter.configure { |config| config.slow_threshold = 0.01 }

RSpec.describe "slow pending" do
  it "shows its duration" do
    pending "known issue"
    sleep 0.02
    raise "expected failure"
  end
end
