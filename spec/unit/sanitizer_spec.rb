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

  it "keeps a valid UTF-8 character split after an invalid prefix" do
    sanitizer = described_class.new

    expect(sanitizer.process("\xFF\xC3".b, "UTF-8")).to eq("\\xFF")
    expect(sanitizer.process("\xA9".b, "UTF-8") + sanitizer.finish).to eq("é")
  end

  it "keeps split UTF-8 and UTF-16 characters intact" do
    utf8 = described_class.new
    expect(utf8.process("aé".encode("UTF-8").byteslice(0, 2))).to eq("a")
    expect(utf8.process("é".encode("UTF-8").byteslice(1, 1))).to eq("é")

    utf16 = described_class.new
    value = "😀".encode("UTF-16LE")
    (0...value.bytesize).each do |split|
      decoder = described_class.new
      first = decoder.process(value.byteslice(0, split), "UTF-16LE")
      second = decoder.process(value.byteslice(split..), "UTF-16LE")
      expect(first + second + decoder.finish).to eq("😀")
    end
  end

  it "keeps BOM-sensitive UTF-16 text intact across every split" do
    value = "A😀雪".encode("UTF-16")

    (0..value.bytesize).each do |split|
      sanitizer = described_class.new
      output = sanitizer.process(value.byteslice(0, split), "UTF-16")
      output << sanitizer.process(value.byteslice(split..), "UTF-16")
      output << sanitizer.finish

      expect(output).to eq("A😀雪"), "failed at byte #{split}"
    end
  end

  it "keeps split legacy multibyte characters intact" do
    value = "あ".encode("Windows-31J")
    sanitizer = described_class.new

    expect(sanitizer.process(value.byteslice(0, 1), "Windows-31J")).to eq("")
    expect(sanitizer.process(value.byteslice(1, 1), "Windows-31J") + sanitizer.finish).to eq("あ")
  end

  it "preserves stateful ISO-2022-JP shift state across writes" do
    value = "あい".encode("ISO-2022-JP")
    sanitizer = described_class.new

    output = value.bytes.each_slice(1).map { |byte| sanitizer.process(byte.pack("C*"), "ISO-2022-JP") }.join
    output << sanitizer.finish

    expect(output).to eq("あい")
  end

  it "escapes incomplete encoded data at shutdown" do
    sanitizer = described_class.new
    value = "😀".encode("UTF-16LE")

    sanitizer.process(value.byteslice(0, 2), "UTF-16LE")

    expect(sanitizer.finish).to eq("\\x3D\\xD8")
  end

  it "retries read-again bytes after malformed multibyte input" do
    sanitizer = described_class.new
    malformed = [0x00, 0xD8, 0x41, 0x00].pack("C*")

    expect(sanitizer.process(malformed, "UTF-16LE")).to eq("\\x00\\xD8A")
  end

  it "escapes unmappable legacy bytes without dropping following text" do
    sanitizer = described_class.new

    expect(sanitizer.process("A\x81\xADZ".b, "Windows-31J")).to eq("A\\x81\\xADZ")
  end

  it "escapes malformed stateful legacy output without raising" do
    sanitizer = described_class.new

    first = sanitizer.process("\x8C\xD3".b, "UTF8-DoCoMo")
    second = sanitizer.process("\x9A\x6F\x8C".b, "UTF8-DoCoMo")
    output = first + second + sanitizer.finish

    expect(output).to start_with("\\x8C")
    expect(output).to include("o")
    expect(output).to end_with("\\x8C")
    expect(output).to be_valid_encoding
  end

  it "keeps UTF8-DoCoMo characters intact across writes" do
    value = "あ".encode("UTF8-DoCoMo")
    sanitizer = described_class.new

    first = sanitizer.process(value.byteslice(0, 1), "UTF8-DoCoMo")
    second = sanitizer.process(value.byteslice(1..), "UTF8-DoCoMo")

    expect(first + second + sanitizer.finish).to eq("あ")
  end

  it "flushes encoding carry when the source encoding changes" do
    sanitizer = described_class.new

    expect(sanitizer.process("\xC3", "UTF-8")).to eq("")
    expect(sanitizer.process("x".b, "ASCII-8BIT")).to eq("\\xC3x")
  end

  it "clears carriage-return state when an entry finishes" do
    sanitizer = described_class.new

    expect(sanitizer.process("first\r")).to eq("first\n")
    expect(sanitizer.finish).to eq("")
    expect(sanitizer.process("\nsecond")).to eq("\nsecond")
  end

  it "flushes escape state before encoding state at shutdown" do
    sanitizer = described_class.new

    sanitizer.process("\e[\xC3".b, "UTF-8")

    expect(sanitizer.finish).to eq("\\e[\\xC3")
  end

  it "parses controls after multibyte text" do
    sanitizer = described_class.new

    expect(sanitizer.process("é\e[31mred\e[0m")).to eq("é\e[31mred\e[0m")
  end

  it "reconstructs an SGR split immediately after ESC" do
    sanitizer = described_class.new

    expect(sanitizer.process("\e")).to eq("")
    expect(sanitizer.process("[31mred")).to eq("\e[31mred")
  end

  it "does not preserve malformed CSI as SGR" do
    sanitizer = described_class.new

    expect(sanitizer.process("x\e[\b31my")).to eq("x\\e[\\x0831my")
    expect(sanitizer.process("x\e[ 31my")).to eq("x\\e[ 31my")
    expect(sanitizer.process("x\e[?25my")).to eq("x\\e[?25my")
  end


  it "escapes ESC before Unicode without corrupting the character" do
    sanitizer = described_class.new

    expect(sanitizer.process("x\e雪y")).to eq("x\\e雪y")
  end

  it "preserves colon-form SGR but still treats other CSI as visible" do
    sanitizer = described_class.new

    expect(sanitizer.process("\e[38:2:255:0:0mred\e[2K")).to eq("\e[38:2:255:0:0mred\\e[2K")
  end

  it "escapes an overlong incomplete control sequence" do
    sanitizer = described_class.new

    expect(sanitizer.process("\e[" + ("1" * 129))).to include("\\e[")
  end
end
