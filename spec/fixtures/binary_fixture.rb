RSpec.describe "binary output" do
  it "writes binary bytes" do
    $stdout.write("binary \xFF".b)
  end
end
