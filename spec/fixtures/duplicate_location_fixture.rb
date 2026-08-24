RSpec.describe "duplicate locations" do
  # Both examples must share a source location for the rerun-id test.
  # standard:disable Style/Semicolon
  it("first") { raise "first failure" }; it("second") { raise "second failure" }
  # standard:enable Style/Semicolon
end
