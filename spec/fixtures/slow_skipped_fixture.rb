RSpec::BetterFormatter.configure { |config| config.slow_threshold = 0 }

RSpec.describe "timed skipped" do
  it "shows its duration", skip: "not available" do
  end
end
