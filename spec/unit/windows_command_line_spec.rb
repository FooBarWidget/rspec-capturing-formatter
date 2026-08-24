require "spec_helper"
require "json"
require "open3"
require "rbconfig"
require "tempfile"

RSpec.describe RSpec::CapturingFormatter::WindowsCommandLine do
  it "preserves ordinary backslashes and quotes trailing backslashes correctly" do
    escaped = described_class.escape(%q(C:\Program Files\specs\car_spec.rb[1:2]))
    trailing = described_class.escape("C:\\specs\\")

    expect(escaped).to include('C:\Program')
    expect(escaped).not_to include("C:\\\\Program")
    expect(trailing).to include('C:\specs\\')
    expect(described_class.escape("%RBF_SENTINEL%", cmd_layers: 2)).to include("%%%%")
    expect(described_class.rerun_argument("C:\\Program Files\\car.rb")).to eq(
      described_class.escape("C:\\Program Files\\car.rb", cmd_layers: 2)
    )
  end

  it "rejects values that cannot form a pasteable one-line command" do
    expect { described_class.escape("spec.rb\nnext") }.to raise_error(ArgumentError)
    expect { described_class.escape("spec.rb\0next") }.to raise_error(ArgumentError)
  end

  it "round-trips special arguments through native cmd.exe" do
    skip "Windows-only command-line round trip" unless Gem.win_platform?

    Dir.mktmpdir("capturing-formatter-cmd") do |directory|
      printer = File.join(directory, "argv_printer.rb")
      launcher = File.join(directory, "rspec.bat")
      File.write(printer, "require 'json'; STDOUT.write(JSON.generate(ARGV))")
      File.write(launcher, "@echo off\r\n\"#{RbConfig.ruby}\" \"#{printer}\" %*\r\n")
      values = [
        %q(C:\Program Files\specs\car_spec.rb:2),
        'quote"inside',
        "trailing\\",
        "%RBF_SENTINEL%",
        "!RBF_SENTINEL!",
        'specs\car_spec.rb[1:2]'
      ]

      values.each do |value|
        body = [launcher, value].map do |argument|
          described_class.rerun_argument(argument)
        end.join(" ")
        stdout, stderr, status = Open3.capture3(
          {"RBF_SENTINEL" => "EXPANDED"},
          ENV.fetch("COMSPEC", "cmd.exe"), "/d", "/v:on", "/s", "/c", body
        )

        expect(status).to be_success, stderr
        expect(JSON.parse(stdout)).to eq([value])
      end
    end
  end
end
