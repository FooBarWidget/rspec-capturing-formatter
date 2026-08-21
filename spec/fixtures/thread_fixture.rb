RSpec.describe "thread output" do
  it "captures a thread write" do
    Thread.new { $stdout.puts "thread output" }.join
  end
end
