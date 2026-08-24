RSpec.configure { |config| config.before(:suite) { raise "suite hook failure" } }

RSpec.describe "hook errors" do
  before(:context) { raise "context hook failure" }

  it("is not run") {}
end
