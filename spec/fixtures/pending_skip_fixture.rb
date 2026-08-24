RSpec::CapturingFormatter.configure { |config| config.pending_failure_output = :skip }

RSpec.describe "pending skip mode" do
  it "omits expected failure details" do
    pending "known issue"
    raise "hidden expected failure"
  end
end
