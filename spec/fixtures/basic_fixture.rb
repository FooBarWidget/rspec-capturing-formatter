RSpec.describe "A car" do
  before do
    $stdout.puts "before hook"
  end

  after do
    warn "after hook"
  end

  it "is red" do
    print "starting engine"
    warn "warning"
    puts " done"
  end

  it "fails" do
    puts "failing now"
    raise "test failure"
  end

  it "waits", skip: "not implemented" do
  end
end
