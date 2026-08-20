require "spec_helper"
require "open3"
require "rbconfig"
require "tempfile"
require "json"

RSpec.describe "the formatter integration" do
  it "captures logs, attributes hooks, and reconciles results" do
    command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      "--no-color",
      File.expand_path("../fixtures/basic_fixture.rb", __dir__)
    ]
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("A car › is red")
    expect(output).to include("stdout | starting engine")
    expect(output).to include("stdout |  done")
    expect(output).to include("stderr | warning")
    expect(output).to include("before hook")
    expect(output).to include("after hook")
    expect(output).to include("succeeded")
    expect(output).to include("failed")
    expect(output).to include("pending")
    expect(output).to include("3 total  1 succeeded  1 failed  1 pending")
    expect(output).to include("Summary")
    expect(output).to include("Failed examples")
  end

  it "restores global streams after the RSpec run" do
    script = <<~RUBY
      $stdout_before = $stdout
      $stderr_before = $stderr
      require "rspec/better_formatter"
      abort "not a proxy" unless $stdout.respond_to?(:source) && $stderr.respond_to?(:source)
      abort "not restored" unless $stdout.equal?($stdout_before) == false
    RUBY
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{File.expand_path("../../lib", __dir__)}", "-e", script
    )

    expect(status).to be_success, stderr + stdout
  end

  it "does not duplicate output captured by RSpec any-process matchers" do
    command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      "--no-color",
      File.expand_path("../fixtures/matcher_fixture.rb", __dir__)
    ]
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output.scan("raw normal").length).to eq(0)
    expect(output.scan("raw stdout").length).to eq(0)
    expect(output.scan("raw stderr").length).to eq(0)
    expect(output.scan("raw child").length).to eq(0)
    expect(output.scan("raw failure").length).to eq(0)
    expect(output).to include("stdout | after matcher")
    expect(output).to include("stdout | after failed matcher")
  end

  it "labels suite and context hooks without repeating contiguous headings" do
    command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      "--no-color",
      File.expand_path("../fixtures/hooks_fixture.rb", __dir__)
    ]
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("RSpec suite")
    expect(output).to include("suite stdout | before suite")
    expect(output).to include("suite stderr | after suite")
    expect(output).to include("A car\n  suite stdout | before context")
    expect(output).to include("A car › in maintenance\n  suite stdout | before nested context")
    expect(output).to include("stdout | example output")
    expect(output.scan("A car › in maintenance\n").length).to eq(1)
  end

  it "renders expected pending details inline" do
    command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      "--no-color",
      File.expand_path("../fixtures/pending_fixture.rb", __dir__)
    ]
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("pending")
    expect(output).to include("reason | known issue")
    expect(output).to include("RuntimeError")
    expect(output).not_to include("Failed examples")
  end

  it "honors pending failure suppression modes" do
    skip_command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      "--no-color",
      File.expand_path("../fixtures/pending_skip_fixture.rb", __dir__)
    ]
    skip_stdout, skip_stderr, skip_status = Open3.capture3(*skip_command)
    skip_output = skip_stdout + skip_stderr
    expect(skip_status).to be_success, skip_output
    expect(skip_output).to include("reason | known issue")
    expect(skip_output).not_to include("hidden expected failure")

    backtrace_command = skip_command.dup
    backtrace_command[-1] = File.expand_path("../fixtures/pending_backtrace_fixture.rb", __dir__)
    backtrace_stdout, backtrace_stderr, backtrace_status = Open3.capture3(*backtrace_command)
    backtrace_output = backtrace_stdout + backtrace_stderr
    expect(backtrace_status).to be_success, backtrace_output
    expect(backtrace_output).to include("expected failure without backtrace")
    expect(backtrace_output).not_to include("# ./")
  end

  it "keeps RSpec presenter details and extra failure lines" do
    command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      "--no-color",
      File.expand_path("../fixtures/failure_metadata_fixture.rb", __dir__)
    ]
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("Failure/Error")
    expect(output).to include("RuntimeError")
    expect(output).to include("diagnostic state: maintenance")
    expect(output).to include("Failed examples")
  end

  it "writes captured output to the formatter destination while keeping JSON separate" do
    Tempfile.create(["better-formatter", ".txt"]) do |report|
      Tempfile.create(["better-formatter", ".json"]) do |json_report|
        command = [
          RbConfig.ruby,
          "-I#{File.expand_path("../../lib", __dir__)}",
          "-S", "rspec",
          "--require", "rspec/better_formatter",
          "--format", "RSpec::BetterFormatter",
          "--out", report.path,
          "--format", "json",
          "--out", json_report.path,
          "--no-color",
          File.expand_path("../fixtures/hooks_fixture.rb", __dir__)
        ]
        stdout, stderr, status = Open3.capture3(*command)

        expect(status).to be_success, stdout + stderr
        expect(File.read(report.path)).to include("suite stdout | before suite")
        expect(JSON.parse(File.read(json_report.path)).fetch("summary").fetch("example_count")).to eq(1)
      end
    end
  end

  it "captures a logger retaining the proxy created after require" do
    command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      "--no-color",
      File.expand_path("../fixtures/logger_fixture.rb", __dir__)
    ]
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("stdout | I, [")
    expect(output).to include("logger message")
  end

  it "applies configuration changes made by loaded spec files" do
    command = [
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-S", "rspec",
      "--require", "rspec/better_formatter",
      "--format", "RSpec::BetterFormatter",
      File.expand_path("../fixtures/configured_fixture.rb", __dir__)
    ]
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("[PASS] succeeded")
    expect(output).not_to include("\e[")
  end
end
