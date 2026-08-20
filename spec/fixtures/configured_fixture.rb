RSpec::BetterFormatter.configure do |config|
  config.color = false
  config.emoji = false
  config.slow_threshold = nil
end

RSpec.describe "configured output" do
  it "uses settings at render time" do
    sleep 0.01
  end
end
