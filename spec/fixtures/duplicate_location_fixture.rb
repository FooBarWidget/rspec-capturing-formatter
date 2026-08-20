RSpec.describe "duplicate locations" do
  it("first") { raise "first failure" }; it("second") { raise "second failure" }
end
