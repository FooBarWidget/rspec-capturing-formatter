require "rspec/expectations"

RSpec.configure { |config| config.include RSpec::Matchers }

RSpec.describe "aggregate failures" do
  it "renders each subfailure" do
    aggregate_failures do
      expect(1).to eq(2)
      expect(:left).to eq(:right)
    end
  end
end
