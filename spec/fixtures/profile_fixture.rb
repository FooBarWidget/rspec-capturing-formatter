RSpec.describe "slow group" do
  it("runs slowly") { sleep 0.02 }
end

RSpec.describe "fast group" do
  it("runs quickly") { sleep 0.001 }
end
