require "spec_helper"
require "stringio"

RSpec.describe RSpec::BetterFormatter::StreamProxy do
  class PassthroughManager
    def handle_write(proxy, value)
      proxy.write_backing(value)
    end

    def bypass
      yield
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

  it "rejects a concurrent formatter without disabling the owner" do
    first = RSpec::BetterFormatter.new(StringIO.new)

    expect { RSpec::BetterFormatter.new(StringIO.new) }.to raise_error(RuntimeError)
    expect(RSpec::BetterFormatter::CaptureManager.instance).to be_active
  ensure
    first&.close
  end
end
