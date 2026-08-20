RSpec.describe "deprecations" do
  it "emits a deprecation" do
    RSpec.deprecate("old API", replacement: "new API")
  end
end
