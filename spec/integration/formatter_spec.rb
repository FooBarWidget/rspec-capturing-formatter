require "spec_helper"
require "open3"
require "rbconfig"
require "tempfile"
require "json"
require "tmpdir"

RSpec.describe "the formatter integration" do
  def rspec_command(*arguments)
    versions = %w[rspec-support rspec-core rspec-expectations rspec-mocks].filter_map do |name|
      spec = Gem.loaded_specs[name]
      [name, spec.version.to_s] if spec
    end
    version = versions.fetch(versions.index { |name, _| name == "rspec-core" }).last
    loader = versions.map { |name, value| "gem \"#{name}\", \"#{value}\"" }.join("; ")
    loader = "#{loader}; load Gem.bin_path(\"rspec-core\", \"rspec\", \"#{version}\")"
    [RbConfig.ruby, "-I#{File.absolute_path("../../lib", __dir__)}", "-e", loader, "--", *arguments]
  end

  def rerun_command(argument)
    escaped = if Gem.win_platform?
      RSpec::CapturingFormatter::WindowsCommandLine.rerun_argument(argument)
    else
      Shellwords.escape(argument)
    end
    "rerun  | rspec #{escaped}"
  end

  it "captures logs, attributes hooks, and reconciles results" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/basic_fixture.rb", __dir__)
    )
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
    expect(output).to include(rerun_command("./spec/fixtures/basic_fixture.rb:16"))
    expect(output).to include("pending")
    expect(output).to include("3 total  1 succeeded  1 failed  1 pending")
    expect(output).to include("Summary")
    expect(output).to include("Failed examples")
  end

  it "restores global streams after the RSpec run" do
    versions = %w[rspec-support rspec-core rspec-expectations rspec-mocks].filter_map do |name|
      spec = Gem.loaded_specs[name]
      "gem #{name.inspect}, #{spec.version.to_s.inspect}" if spec
    end.join("\n")
    script = <<~RUBY
      #{versions}
      original_stdout = $stdout
      original_stderr = $stderr
      require "rspec/capturing_formatter"
      require "rspec/core/sandbox"
      fixture = #{File.absolute_path("../fixtures/configured_fixture.rb", __dir__).inspect}

      2.times do |index|
        status = nil
        RSpec::Core::Sandbox.sandboxed do
          status = RSpec::Core::Runner.run(["--format", "RSpec::CapturingFormatter", "--no-color", fixture])
        end
        abort "run failed" unless status.zero?
        abort "stdout not restored after run \#{index}" unless $stdout.equal?(original_stdout)
        abort "stderr not restored after run \#{index}" unless $stderr.equal?(original_stderr)
      end
      puts "streams restored"
    RUBY
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{File.absolute_path("../../lib", __dir__)}", "-e", script
    )

    expect(status).to be_success, stderr + stdout
    expect(stdout).to include("streams restored")
  end

  it "restores globals when formatter setup fails before activation" do
    script = <<~RUBY
      require "stringio"
      require "rspec/capturing_formatter"
      manager = RSpec::CapturingFormatter::CaptureManager.instance
      original_stdout = manager.stdout_proxy.backing
      original_stderr = manager.stderr_proxy.backing
      RSpec::CapturingFormatter::Renderer.define_singleton_method(:new) { |*| raise "setup failed" }

      begin
        RSpec::CapturingFormatter.new(StringIO.new)
      rescue => error
        abort "wrong error" unless error.message == "setup failed"
      end
      abort "manager remained active" if manager.active?
      abort "stdout not restored" unless $stdout.equal?(original_stdout)
      abort "stderr not restored" unless $stderr.equal?(original_stderr)
    RUBY
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{File.absolute_path("../../lib", __dir__)}", "-e", script
    )

    expect(status).to be_success, stdout + stderr
  end

  it "does not duplicate output captured by RSpec any-process matchers" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/matcher_fixture.rb", __dir__)
    )
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
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/hooks_fixture.rb", __dir__)
    )
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
    expect(output.scan("RSpec suite\n").length).to eq(1)
    expect(output.scan("A car\n").length).to eq(1)
  end

  it "renders expected pending details inline" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/pending_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("pending")
    expect(output).to include("reason | known issue")
    expect(output).to include("RuntimeError")
    expect(output).not_to include("Failed examples")
  end

  it "honors pending failure suppression modes" do
    skip_command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/pending_skip_fixture.rb", __dir__)
    )
    skip_stdout, skip_stderr, skip_status = Open3.capture3(*skip_command)
    skip_output = skip_stdout + skip_stderr
    expect(skip_status).to be_success, skip_output
    expect(skip_output).to include("reason | known issue")
    expect(skip_output).not_to include("hidden expected failure")

    backtrace_command = skip_command.dup
    backtrace_command[-1] = File.absolute_path("../fixtures/pending_backtrace_fixture.rb", __dir__)
    backtrace_command[backtrace_command.index("--no-color")] = "--force-color"
    backtrace_stdout, backtrace_stderr, backtrace_status = Open3.capture3(*backtrace_command)
    backtrace_output = backtrace_stdout + backtrace_stderr
    expect(backtrace_status).to be_success, backtrace_output
    expect(backtrace_output).to include("expected failure without backtrace")
    expect(backtrace_output.gsub(/\e\[[0-?]*[ -\/]*[@-~]/, "")).not_to include("# ./")
  end

  it "keeps RSpec presenter details and extra failure lines" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/failure_metadata_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("Failure/Error")
    expect(output).to include("RuntimeError")
    expect(output).to include("diagnostic state: maintenance")
    expect(output).to include("Failed examples")
  end

  it "writes captured output to the formatter destination while keeping JSON separate" do
    Tempfile.create(["capturing-formatter", ".txt"]) do |report|
      Tempfile.create(["capturing-formatter", ".json"]) do |json_report|
        command = rspec_command(
          "--require", "rspec/capturing_formatter",
          "--format", "RSpec::CapturingFormatter",
          "--out", report.path,
          "--format", "json",
          "--out", json_report.path,
          "--no-color",
          File.absolute_path("../fixtures/hooks_fixture.rb", __dir__)
        )
        stdout, stderr, status = Open3.capture3(*command)

        expect(status).to be_success, stdout + stderr
        expect(File.read(report.path)).to include("suite stdout | before suite")
        expect(JSON.parse(File.read(json_report.path)).fetch("summary").fetch("example_count")).to eq(1)
      end
    end
  end

  it "captures a logger retaining the proxy created after require" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/logger_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("stdout | I, [")
    expect(output).to include("logger message")
  end

  it "captures output written from an example thread" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/thread_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("stdout | thread output")
  end

  it "renders binary captured output safely" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/binary_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("stdout | binary \\xFF")
  end

  it "joins an encoded character split across writes" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/encoding_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("stdout | price \u20AC")
  end

  it "reports a fixed pending example as failed" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/fixed_pending_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("failed")
    expect(output).to include("1 total  0 succeeded  1 failed  0 pending")
  end

  it "applies configuration changes made by loaded spec files" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      File.absolute_path("../fixtures/configured_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("[PASS] succeeded")
    expect(output).not_to include("\e[")
  end

  it "enables default non-TTY color and honors NO_COLOR" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      File.absolute_path("../fixtures/basic_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    expect(status).not_to be_success, stdout + stderr
    expect(stdout + stderr).to include("\e[")

    no_color_stdout, no_color_stderr, no_color_status = Open3.capture3(
      {"NO_COLOR" => "1"}, *command
    )
    expect(no_color_status).not_to be_success, no_color_stdout + no_color_stderr
    expect(no_color_stdout + no_color_stderr).not_to include("\e[")
  end

  it "preserves RSpec deprecation output" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/deprecation_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("1 deprecation warning total")
    expect(output).to include("old API is deprecated")
  end

  it "passes output after formatter shutdown through unchanged" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/after_stop_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("after formatter stop\n")
    expect(output).not_to include("stdout | after formatter stop")
  end

  it "includes profile totals and example locations" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--profile", "1",
      "--no-color",
      File.absolute_path("../fixtures/profile_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("Profile")
    expect(output).to include("Slowest examples total")
    expect(output).to include("profile_fixture.rb:")
    expect(output).to include("Slowest example groups")
    expect(output).to include("average")
    expect(output).to include("1 examples")
  end

  it "keeps an empty profile section visible" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--profile", "0",
      "--no-color",
      File.absolute_path("../fixtures/profile_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("Profile")
    expect(output).to include("No examples profiled")
  end

  it "shows qualifying durations for pending examples" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/slow_pending_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to match(/pending\s+\d+ ms/)
  end

  it "shows qualifying durations for skipped examples" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/slow_skipped_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to match(/skipped\s+\d+ ms/)
  end

  it "uses example ids when failed examples share a location" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/duplicate_location_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include(rerun_command("./spec/fixtures/duplicate_location_fixture.rb[1:1]"))
    expect(output).to include(rerun_command("./spec/fixtures/duplicate_location_fixture.rb[1:2]"))
  end

  it "preserves aggregate failure details from RSpec" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/aggregate_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("expected: 2")
    expect(output).to include("expected: :right")
  end

  it "preserves shared-example traces from RSpec" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/shared_example_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("Shared Example Group: \"a shared failure\"")
    expect(output).to include("shared failure")
  end

  it "keeps pre-start messages and prints a used random seed in the final phase" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--order", "rand:123",
      "--tag", "focus",
      "--no-color",
      File.absolute_path("../fixtures/hooks_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("rspec | Run options")
    expect(output).to include("Randomized with seed 123")
    expect(output.index("rspec | Run options")).to be < output.index("suite stdout | before suite")
    expect(output.index("Summary")).to be < output.index("Randomized with seed 123")
  end

  it "reports errors raised outside examples separately" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/hook_error_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("rspec | Failure/Error")
    expect(output).to include("suite hook failure")
    expect(output).to include("1 errors outside examples")
  end

  it "preserves context hook failures inline" do
    command = rspec_command(
      "--require", "rspec/capturing_formatter",
      "--format", "RSpec::CapturingFormatter",
      "--no-color",
      File.absolute_path("../fixtures/context_hook_error_fixture.rb", __dir__)
    )
    stdout, stderr, status = Open3.capture3(*command)
    output = stdout + stderr

    expect(status).not_to be_success
    expect(output).to include("context hook failure")
    expect(output).to include("Failure/Error")
  end

  it "restores streams when fail-fast stops the suite" do
    versions = %w[rspec-support rspec-core rspec-expectations rspec-mocks].filter_map do |name|
      spec = Gem.loaded_specs[name]
      "gem #{name.inspect}, #{spec.version.to_s.inspect}" if spec
    end.join("\n")
    script = <<~RUBY
      #{versions}
      original_stdout = $stdout
      original_stderr = $stderr
      require "rspec/capturing_formatter"
      status = RSpec::Core::Runner.run([
        "--format", "RSpec::CapturingFormatter", "--no-color", "--order", "defined", "--fail-fast=1",
        #{File.absolute_path("../fixtures/fail_fast_fixture.rb", __dir__).inspect}
      ])
      abort "expected failure" unless status == 1
      abort "stdout not restored" unless $stdout.equal?(original_stdout)
      abort "stderr not restored" unless $stderr.equal?(original_stderr)
      puts "after fail fast"
    RUBY
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I#{File.absolute_path("../../lib", __dir__)}", "-e", script
    )
    output = stdout + stderr

    expect(status).to be_success, output
    expect(output).to include("after fail fast\n")
    expect(output).not_to include("FAIL FAST DID NOT STOP")
    expect(output).not_to include("stdout | after fail fast")
  end

  it "builds and loads the installed gem" do
    Dir.mktmpdir("capturing-formatter-package") do |directory|
      gem_path = File.join(directory, "rspec-capturing-formatter.gem")
      build_stdout, build_stderr, build_status = Open3.capture3(
        "gem", "build", "rspec-capturing-formatter.gemspec", "--output", gem_path,
        chdir: File.absolute_path("../..", __dir__)
      )
      expect(build_status).to be_success, build_stdout + build_stderr

      install_dir = File.join(directory, "install")
      install_stdout, install_stderr, install_status = Open3.capture3(
        "gem", "install", gem_path, "--install-dir", install_dir,
        "--ignore-dependencies", "--no-document"
      )
      expect(install_status).to be_success, install_stdout + install_stderr

      installed_gem_dir = Dir.glob(File.join(install_dir, "gems", "rspec-capturing-formatter-*")).fetch(0)
      gem_path_env = ([install_dir] + Gem.path).join(File::PATH_SEPARATOR)
      smoke_stdout, smoke_stderr, smoke_status = Bundler.with_unbundled_env do
        Open3.capture3(
          {
            "GEM_HOME" => install_dir,
            "GEM_PATH" => gem_path_env,
            "INSTALLED_GEM_DIR" => installed_gem_dir
          },
          RbConfig.ruby, "-I#{File.join(installed_gem_dir, "lib")}", "-e",
          <<~RUBY
            require "rspec/capturing_formatter"
            installed_gem_dir = File.absolute_path(ENV.fetch("INSTALLED_GEM_DIR"))
            installed_formatter_path = File.join(installed_gem_dir, "lib", "rspec", "capturing_formatter.rb")
            abort "did not load the installed gem: \#{installed_formatter_path}" unless $LOADED_FEATURES.include?(installed_formatter_path)
          RUBY
        )
      end
      expect(smoke_status).to be_success, smoke_stdout + smoke_stderr
    end
  end
end
