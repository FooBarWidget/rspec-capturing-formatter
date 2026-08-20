RSpec.describe "failure details" do
  it "includes extra metadata", extra_failure_lines: ["diagnostic state: maintenance"] do
    raise "detailed failure"
  end
end
