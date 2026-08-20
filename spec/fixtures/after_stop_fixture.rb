RSpec.describe "shutdown output" do
  it("passes") { }
end

at_exit do
  puts "after formatter stop"
end
