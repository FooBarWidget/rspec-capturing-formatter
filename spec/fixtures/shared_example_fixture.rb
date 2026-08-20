RSpec.shared_examples "a shared failure" do
  it("fails from shared code") { raise "shared failure" }
end

RSpec.describe "shared behavior" do
  include_examples "a shared failure"
end
