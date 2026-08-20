require "spec_helper"

RSpec.describe RSpec::BetterFormatter::Sanitizer do
  it "normalizes carriage returns and preserves SGR" do
    sanitizer = described_class.new

    expect(sanitizer.process("one\r\ntwo\rthree\e[31mred\e[0m\n")).to eq(
      "one\ntwo\nthree\e[31mred\e[0m\n"
    )
  end

  it "renders terminal controls instead of executing them" do
    sanitizer = described_class.new

    expect(sanitizer.process("a\b\e[2K\e]0;title\a\n")).to eq(
      "a\\x08\\e[2K\\e]0;title\\x07\n"
    )
  end

  it "handles an escape sequence split across writes" do
    sanitizer = described_class.new

    expect(sanitizer.process("hello\e[")).to eq("hello")
    expect(sanitizer.process("31mred\n")).to eq("\e[31mred\n")
  end

  it "escapes an incomplete sequence at a boundary" do
    sanitizer = described_class.new

    expect(sanitizer.process("hello\e[")).to eq("hello")
    expect(sanitizer.finish).to eq("\\e[")
  end

  it "escapes invalid and binary bytes" do
    sanitizer = described_class.new

    expect(sanitizer.process("ok\xff", "ASCII-8BIT")).to eq("ok\\xFF")
    expect(sanitizer.process("\xFF".b, "UTF-8")).to eq("\\xFF")
  end

  it "keeps split UTF-8 and UTF-16 characters intact" do
    utf8 = described_class.new
    expect(utf8.process("é".encode("UTF-8").byteslice(0, 1))).to eq("")
    expect(utf8.process("é".encode("UTF-8").byteslice(1, 1))).to eq("é")

    utf16 = described_class.new
    value = "雪".encode("UTF-16LE")
    expect(utf16.process(value.byteslice(0, 1), "UTF-16LE")).to eq("")
    expect(utf16.process(value.byteslice(1, 1), "UTF-16LE")).to eq("雪")
  end

  it "parses controls after multibyte text" do
    sanitizer = described_class.new

    expect(sanitizer.process("é\e[31mred\e[0m")).to eq("é\e[31mred\e[0m")
  end
end
