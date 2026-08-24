require "spec_helper"
require "stringio"

RSpec.describe RSpec::CapturingFormatter::Renderer do
  let(:output) { StringIO.new }
  let(:configuration) do
    RSpec::CapturingFormatter::Configuration.new.tap do |value|
      value.color = false
      value.emoji = false
    end
  end
  subject(:renderer) { described_class.new(output, configuration) }

  it "keeps formatter entries append-only with one blank line between them" do
    renderer.example_started("A car › it is red")
    renderer.result(:passed, 0.01)
    renderer.context_started("A car › during maintenance")
    renderer.capture("suite stdout", "preparing\n")

    expect(output.string).to eq(
      "A car › it is red\n  [PASS] succeeded\n\n" \
      "A car › during maintenance\n  suite stdout | preparing\n"
    )
  end

  it "prints example descriptions in bold when color is enabled" do
    configuration.color = true

    renderer.example_started("A car › it is red")

    expect(output.string).to eq("\e[0m\e[1mA car › it is red\e[0m\n")
  end

  it "colors durations that meet the slow threshold pink" do
    configuration.color = true

    renderer.example_started("A car › it is slow")
    renderer.result(:passed, 0.75)

    expect(output.string).to include("\e[95m  750 ms\e[0m")
  end

  it "keeps the summary header bold and colors passing summary text green" do
    configuration.color = true

    renderer.summary(total: 1, succeeded: 1, failed: 0, pending: 0, duration: 0.1, load_time: 0.01)

    expect(output.string).to include("\e[0m\e[1mSummary\e[0m\n")
    expect(output.string).to include("\e[32m  1 total  1 succeeded  0 failed  0 pending\e[0m")
  end

  it "keeps the summary header bold and colors failing summary text red" do
    configuration.color = true

    renderer.summary(total: 1, succeeded: 0, failed: 1, pending: 0, duration: 0.1, load_time: 0.01)

    expect(output.string).to include("\e[0m\e[1mSummary\e[0m\n")
    expect(output.string).to include("\e[31m  1 total  0 succeeded  1 failed  0 pending\e[0m")
  end

  it "colors plain stdout and stderr payloads" do
    configuration.color = true

    renderer.example_started("A car › it logs")
    renderer.capture("stdout", "plain output\n")
    renderer.capture("stderr", "warning output\n")

    expect(output.string).to include("\e[90m  stdout | \e[0m\e[90mplain output\e[0m\e[0m\n")
    expect(output.string).to include("\e[33m  stderr | \e[0m\e[33mwarning output\e[0m\e[0m\n")
  end

  it "keeps application colors after the source prefix" do
    configuration.color = true

    renderer.example_started("A car › it logs")
    renderer.capture("stdout", "\e[31mred output\e[0m\n")

    expect(output.string).to include("\e[90m  stdout | \e[0m\e[31mred output\e[0m\e[0m\n")
  end

  it "omits formatter and application colors when ANSI is unsupported" do
    configuration.color = true
    renderer = described_class.new(output, configuration, ansi_supported: false)

    renderer.example_started("A car › it logs")
    renderer.capture("stdout", "\e[31mred output\e[0m\n")
    renderer.failure(["\e[31mFailure/Error: broken\e[0m"])
    renderer.result(:passed, 0.01)

    expect(output.string).to eq(
      "A car › it logs\n  stdout | red output\n  Failure/Error: broken\n  [PASS] succeeded\n"
    )
    expect(output.string).not_to include("\e[")
  end

  it "shows qualifying durations for pending and skipped examples" do
    renderer.example_started("A car › it is pending")
    renderer.pending("known issue", "rspec spec/car_spec.rb:1", run_time: 0.75)
    renderer.example_started("A car › it is skipped")
    renderer.pending("not available", "rspec spec/car_spec.rb:2", skipped: true, run_time: 1.25)

    expect(output.string).to eq(
      "A car › it is pending\n  [PENDING] pending  750 ms\n" \
      "  reason | known issue\n  rerun  | rspec spec/car_spec.rb:1\n\n" \
      "A car › it is skipped\n  [SKIP] skipped  1.25 s\n" \
      "  reason | not available\n  rerun  | rspec spec/car_spec.rb:2\n"
    )
  end

  it "flushes partial lines and labels each physical line" do
    renderer.example_started("A car › it beeps")
    renderer.capture("stdout", "starting")
    renderer.capture("stdout", " engine\nnext\n")
    renderer.capture("stderr", "warning")
    renderer.result(:passed, 0.01)

    expect(output.string).to include("  stdout | starting engine\n  stdout | next\n")
    expect(output.string).to include("  stderr | warning\n  [PASS] succeeded\n")
  end

  it "resets captured application styling before formatter output" do
    renderer.example_started("A car › it is red")
    renderer.capture("stdout", "\e[31mred")
    renderer.result(:passed, 0.01)

    expect(output.string).to include("stdout | \e[31mred\e[0m\n")
    expect(output.string).to include("  [PASS] succeeded\n")
  end

  it "keeps RSpec messages inside the active example entry" do
    renderer.example_started("A car › it reports")
    renderer.capture("stdout", "partial")
    renderer.message("Failure/Error: diagnostic\nRuntimeError: broken", inside_example: true)
    renderer.capture("stdout", "continued\n")
    renderer.result(:failed, 0.01)

    expect(output.string).to include("stdout | partial\n  rspec | Failure/Error: diagnostic\n")
    expect(output.string).to include("  rspec | RuntimeError: broken\n  stdout | continued\n")
  end

  it "resets modern application SGR before formatter-owned status output" do
    renderer.example_started("A car › it is colorful")
    renderer.capture("stdout", "\e[38:2:255:0:0mred\e[0m\n")
    renderer.result(:passed, 0.01)

    expect(output.string).to include("\e[38:2:255:0:0mred\e[0m\n\e[0m  [PASS]")
  end

  it "writes valid text to a UTF-16 report destination" do
    output = StringIO.new
    output.set_encoding("UTF-16LE")
    renderer = described_class.new(output, configuration)

    renderer.example_started("A car › it is red")
    renderer.result(:passed, 0.01)

    decoded = output.string.dup.force_encoding("UTF-16LE").encode("UTF-8")
    expect(decoded).to include("A car › it is red")
    expect(decoded).to include("[PASS] succeeded")
  end

  it "writes only one BOM to a BOM-sensitive destination" do
    output = StringIO.new
    output.set_encoding("UTF-16")
    renderer = described_class.new(output, configuration)

    renderer.example_started("A car › it is red")
    renderer.result(:passed, 0.01)

    decoded = output.string.dup.force_encoding("UTF-16").encode("UTF-8")
    expect(decoded).to include("A car › it is red")
    expect(decoded.scan("\uFEFF").length).to be <= 1
  end

  it "escapes unrepresentable characters for legacy report encodings" do
    output = StringIO.new
    output.set_encoding("ISO-2022-JP")
    renderer = described_class.new(output, configuration)

    renderer.example_started("A 😀")
    renderer.result(:passed, 0.01)

    decoded = output.string.encode("UTF-8")
    expect(decoded).to include("\\u{1F600}")
    expect(decoded).to include("[PASS] succeeded")
  end
end
