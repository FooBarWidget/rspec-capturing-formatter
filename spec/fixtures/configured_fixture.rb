RSpec::CapturingFormatter.configure do |config|
  config.color = false
  config.emoji = false
  config.slow_threshold = nil
end

RSpec.describe "configured output" do
  it "uses settings at render time" do
  end
end
