require "rbconfig"
require "rspec/expectations"

RSpec.configure { |config| config.include RSpec::Matchers }

RSpec.describe "stream matchers" do
  it "captures output from the current process" do
    expect { $stdout.puts "raw normal" }.to output("raw normal\n").to_stdout
    expect { $stdout.puts "raw stdout" }.to output("raw stdout\n").to_stdout_from_any_process
    expect { warn "raw stderr" }.to output("raw stderr\n").to_stderr_from_any_process
    expect {
      system(RbConfig.ruby, "-e", "STDOUT.write('raw child\n')")
    }.to output("raw child\n").to_stdout_from_any_process
    puts "after matcher"
  end

  it "restores streams after matcher failures" do
    expect {
      expect { $stdout.puts "raw failure" }.to output("wrong\n").to_stdout_from_any_process
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    expect {
      system(RbConfig.ruby, "-e", "STDOUT.write('child after failure\n')")
    }.to output("child after failure\n").to_stdout_from_any_process
    puts "after failed matcher"
  end
end
