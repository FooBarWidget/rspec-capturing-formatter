RSpec.configure do |config|
  config.before(:suite) { puts "before suite" }
  config.after(:suite) { warn "after suite" }
end

RSpec.describe "A car" do
  before(:context) { puts "before context" }
  after(:context) { puts "after context" }

  context "in maintenance" do
    before(:context) { puts "before nested context" }

    it("works") { puts "example output" }
  end
end
