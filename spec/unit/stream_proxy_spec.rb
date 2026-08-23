require "spec_helper"
require "stringio"

RSpec.describe RSpec::BetterFormatter::StreamProxy do
  class PassthroughManager
    def handle_write(proxy, value, method = :write, **options)
      proxy.write_backing(value, method, **options)
    end

    def bypass
      yield
    end

    def synchronize
      yield
    end
  end

  class NativePassthrough
    attr_reader :calls

    def initialize
      @calls = []
    end

    def write(*)
      raise "ordinary write was used"
    end

    def write_nonblock(value, exception: true)
      @calls << [:write_nonblock, value, exception]
      value.bytesize - 1
    end

    def syswrite(value)
      @calls << [:syswrite, value]
      value.bytesize - 2
    end
  end

  let(:manager) { PassthroughManager.new }
  let(:backing) { StringIO.new }
  subject(:proxy) { described_class.new(backing, :stdout, manager) }

  it "matches writable IO return values and puts semantics" do
    expect(proxy.write("abc")).to eq(3)
    expect(proxy << "def").to equal(proxy)
    expect(proxy.puts).to be_nil
    expect(proxy.puts(nil, ["one", "two"], "done\n")).to be_nil
    expect(proxy.print("x", "y")).to be_nil
    expect(proxy.putc("z")).to eq("z")
    expect(backing.string).to eq("abcdef\n\none\ntwo\ndone\nxyz")
  end

  it "puts UTF-16 strings with an encoded newline" do
    backing.set_encoding("UTF-16LE")
    value = "雪".encode("UTF-16LE")

    proxy.puts(value)

    expect(backing.string.encode("UTF-8")).to eq("雪\n")
  end

  it "reopens to a raw stream and restores from a deep clone" do
    original = proxy.clone
    temporary = StringIO.new

    proxy.reopen(temporary)
    proxy.puts "raw"
    expect(temporary.string).to eq("raw\n")

    proxy.reopen(original)
    proxy.puts "restored"
    expect(original.backing.string).to eq("restored\n")
  end

  it "restores nested reopen pairs in order" do
    outer = proxy.clone
    first = StringIO.new
    second = StringIO.new

    proxy.reopen(first)
    inner = proxy.clone
    proxy.reopen(second)
    proxy.puts "second"
    proxy.reopen(inner)
    proxy.puts "first"
    proxy.reopen(outer)
    proxy.puts "original"

    expect(second.string).to eq("second\n")
    expect(first.string).to eq("first\n")
    expect(outer.backing.string).to eq("original\n")
  end

  it "delegates read-only capabilities and preserves encoding" do
    expect(proxy.to_io).to equal(proxy)
    expect(proxy.external_encoding).to eq(Encoding::UTF_8)
    expect(proxy.respond_to?(:path)).to be(false)
    expect(proxy.fileno).to be_nil
  end

  it "preserves print, putc, and recursive puts behavior" do
    original_record_separator = $OUTPUT_RECORD_SEPARATOR
    original_field_separator = $OUTPUT_FIELD_SEPARATOR
    original_last_line = $_
    $OUTPUT_RECORD_SEPARATOR = "!"
    $OUTPUT_FIELD_SEPARATOR = ","
    $_ = "last"
    recursive = []
    recursive << recursive

    proxy.print
    proxy.putc(300)
    proxy.puts(recursive)

    expect(backing.string).to eq(",[...]\n")
  ensure
    $OUTPUT_RECORD_SEPARATOR = original_record_separator
    $OUTPUT_FIELD_SEPARATOR = original_field_separator
    $_ = original_last_line
  end

  it "delegates nonblocking writes while inactive" do
    expect(proxy.write_nonblock("abc", exception: false)).to eq(3)
    expect(proxy.syswrite("def")).to eq(3)
    expect(backing.string).to eq("abcdef")
  end

  it "uses native nonblocking and syswrite methods in passthrough mode" do
    native_backing = NativePassthrough.new
    native_proxy = described_class.new(native_backing, :stdout, manager)

    expect(native_proxy.write_nonblock("abc")).to eq(2)
    expect(native_proxy.write_nonblock("def", exception: false)).to eq(2)
    expect(native_proxy.syswrite("ghi")).to eq(1)
    expect(native_backing.calls).to eq([
      [:write_nonblock, "abc", true],
      [:write_nonblock, "def", false],
      [:syswrite, "ghi"]
    ])
  end

  it "returns wait_writable for a nonblocking capture write when requested" do
    blocking_manager = Class.new do
      def handle_write(*)
        raise Errno::EAGAIN
      end
    end.new
    blocking_proxy = described_class.new(StringIO.new, :stdout, blocking_manager)

    expect(blocking_proxy.write_nonblock("x", exception: false)).to eq(:wait_writable)
    expect { blocking_proxy.write_nonblock("x") }.to raise_error(Errno::EAGAIN)
  end

  it "rejects a concurrent formatter without disabling the owner" do
    first = RSpec::BetterFormatter.new(StringIO.new)

    expect { RSpec::BetterFormatter.new(StringIO.new) }.to raise_error(RuntimeError)
    expect(RSpec::BetterFormatter::CaptureManager.instance).to be_active
  ensure
    first&.close
  end
end
