RSpec.describe "fail fast cleanup" do
  it("fails first") { raise "stop now" }
  it("must not run") { puts "FAIL FAST DID NOT STOP" }
end
