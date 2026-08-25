require "spec_helper"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe RSpec::CapturingFormatter::WindowsCommandLine do
  it "preserves ordinary backslashes and quotes trailing backslashes correctly" do
    escaped = described_class.escape(%q(C:\Program Files\specs\car_spec.rb[1:2]))
    trailing = described_class.escape("C:\\specs\\")

    expect(escaped).to include('C:\Program')
    expect(escaped).not_to include("C:\\\\Program")
    expect(trailing).to include('C:\specs\\')
  end

  it "encodes dynamic rerun arguments outside cmd.exe syntax" do
    command = described_class.rerun_command("%RBF_SENTINEL%!RBF_SENTINEL!")

    expect(command).not_to include("%RBF_SENTINEL%", "!RBF_SENTINEL!")
    expect(command).to end_with(["%RBF_SENTINEL%!RBF_SENTINEL!"].pack("m0"))
  end

  it "decodes the target before loading RSpec" do
    Dir.mktmpdir("capturing-formatter-rerun") do |directory|
      spec = File.join(directory, "rerun_spec.rb")
      File.write(spec, "RSpec.describe('rerun') { it('passes') { expect(1).to eq(1) } }")
      bootstrap = "#{described_class::DECODE_ARGUMENT};#{described_class::RUN_RSPEC}"
      encoded = [spec.encode(Encoding::UTF_8)].pack("m0")

      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", bootstrap, encoded, "--format", "progress")

      expect(status).to be_success, stderr
      expect(stdout).to include("1 example, 0 failures")
    end
  end

  it "rejects values that cannot form a pasteable one-line command" do
    expect { described_class.escape("spec.rb\nnext") }.to raise_error(ArgumentError)
    expect { described_class.escape("spec.rb\0next") }.to raise_error(ArgumentError)
    expect { described_class.escape("%TEMP%") }.to raise_error(ArgumentError, /must be encoded/)
    expect { described_class.escape("!TEMP!") }.to raise_error(ArgumentError, /must be encoded/)
  end

  it "round-trips special arguments through native cmd.exe", :aggregate_failures do
    skip "Windows-only command-line round trip" unless Gem.win_platform?

    Dir.mktmpdir("capturing-formatter-cmd") do |directory|
      output = File.join(directory, "argv.bin")
      printer = "STDOUT.binmode;STDOUT.write(ARGV.fetch(0))"
      values = [
        %q(C:\Program Files\specs\car_spec.rb:2),
        'quote"inside',
        "trailing\\",
        "%RBF_SENTINEL%",
        "!RBF_SENTINEL!",
        "specs\\café_spec.rb:2",
        'specs\car_spec.rb[1:2]'
      ]
      values.each do |value|
        command = described_class.encoded_ruby_command(printer, value)
        # Redirect the payload so the interactive shell's banner and prompt do not
        # affect the assertion.
        _stdout, stderr, status = Open3.capture3(
          {"RBF_SENTINEL" => "EXPANDED"},
          ENV.fetch("COMSPEC", "cmd.exe"), "/d", "/v:on", "/q",
          chdir: directory,
          stdin_data: "#{command} > \"#{output}\"\r\nexit\r\n"
        )

        expect(status).to be_success, stderr
        expect(File.binread(output).force_encoding(Encoding::UTF_8)).to eq(value)
      end
    end
  end

  it "passes encoded rerun command argv through Wine cmd.exe" do
    skip "native Windows coverage runs separately" if Gem.win_platform?
    skip "Wine and winegcc are required" unless system("wine", "--version", out: File::NULL, err: File::NULL) &&
      system("winegcc", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir("capturing-formatter-wine") do |directory|
      source = File.absolute_path("../fixtures/windows_argv_printer.c", __dir__)
      printer = File.join(directory, "argv_printer.exe")
      _stdout, stderr, status = Open3.capture3("winegcc", source, "-o", printer)
      expect(status).to be_success, stderr

      printer_windows = wine_path(printer)
      output = File.join(directory, "argv.bin")
      output_windows = wine_path(output)
      value = "C:\\Program Files\\quote\"inside\\trailing\\%RBF_SENTINEL%!RBF_SENTINEL![1:2] café"
      rerun = described_class.rerun_command(value)
      command = rerun.sub(/\Aruby /, "#{described_class.escape(printer_windows)} ")
      _stdout, stderr, status = Open3.capture3(
        {"RBF_SENTINEL" => "EXPANDED", "WINEDEBUG" => "-all"},
        "wine", "cmd", "/d", "/v:on", "/q",
        stdin_data: "#{command} > #{described_class.escape(output_windows)}\r\nexit\r\n"
      )
      expect(status).to be_success, stderr

      expect(File.binread(output).split("\0")).to eq([
        "-e",
        "#{described_class::DECODE_ARGUMENT};#{described_class::RUN_RSPEC}",
        [value.encode(Encoding::UTF_8)].pack("m0")
      ])
    end
  end

  def wine_path(path)
    stdout, stderr, status = Open3.capture3({"WINEDEBUG" => "-all"}, "winepath", "-w", path)
    raise stderr unless status.success?

    stdout.strip
  end
end
