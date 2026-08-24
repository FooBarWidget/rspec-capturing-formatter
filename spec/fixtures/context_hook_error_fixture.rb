RSpec.describe "context hook errors" do
  before(:context) { raise "context hook failure" }

  it("is not run") {}
end
