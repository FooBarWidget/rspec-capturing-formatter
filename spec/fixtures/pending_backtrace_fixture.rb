RSpec.configure { |config| config.pending_failure_output = :no_backtrace }

RSpec.describe "pending backtrace mode" do
  it "keeps details without a backtrace" do
    pending "known issue"
    raise "expected failure without backtrace"
  end
end
