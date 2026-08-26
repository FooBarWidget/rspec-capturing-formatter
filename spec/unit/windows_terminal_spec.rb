require "spec_helper"
require "fiddle"

RSpec.describe RSpec::CapturingFormatter::WindowsTerminal do
  let(:output) { instance_double("output", tty?: true) }
  let(:api) { instance_double("native api") }

  it "keeps ANSI support on non-Windows platforms" do
    expect(api).not_to receive(:enable_virtual_terminal_processing)

    expect(described_class.ansi_supported?(output, on_windows: false, api: api)).to be(true)
  end

  it "keeps ANSI support for redirected Windows output" do
    expect(api).not_to receive(:enable_virtual_terminal_processing)

    expect(
      described_class.ansi_supported?(instance_double("output", tty?: false), on_windows: true, api: api)
    ).to be(true)
  end

  it "rejects interactive output outside Windows Terminal" do
    expect(api).not_to receive(:enable_virtual_terminal_processing)

    expect(described_class.ansi_supported?(output, on_windows: true, env: {}, api: api)).to be(false)
  end

  it "enables ANSI support in Windows Terminal" do
    expect(api).to receive(:enable_virtual_terminal_processing).with(output).and_return(true)

    expect(
      described_class.ansi_supported?(output, on_windows: true, env: {"WT_SESSION" => "session"}, api: api)
    ).to be(true)
  end

  it "rejects Windows Terminal output when VT mode cannot be enabled" do
    expect(api).to receive(:enable_virtual_terminal_processing).with(output).and_return(false)

    expect(
      described_class.ansi_supported?(output, on_windows: true, env: {"WT_SESSION" => "session"}, api: api)
    ).to be(false)
  end

  it "falls back when the Windows API cannot be loaded" do
    allow(api).to receive(:enable_virtual_terminal_processing).and_raise(Fiddle::DLError)

    expect(
      described_class.ansi_supported?(output, on_windows: true, env: {"WT_SESSION" => "session"}, api: api)
    ).to be(false)
  end

  it "does not hide unrelated API errors" do
    allow(api).to receive(:enable_virtual_terminal_processing).and_raise(ArgumentError, "bad API setup")

    expect {
      described_class.ansi_supported?(output, on_windows: true, env: {"WT_SESSION" => "session"}, api: api)
    }.to raise_error(ArgumentError, "bad API setup")
  end
end
