require "spec_helper"
require "stringio"

RSpec.describe RSpec::BetterFormatter::CaptureManager do
  it "does not let a stale owning lease stop a later run" do
    manager = described_class.new
    output_a = StringIO.new
    output_b = StringIO.new
    formatter = double(:formatter, finish_capture: nil)

    lease_a = manager.activate(output_a, formatter)
    manager.deactivate(lease_a)
    lease_b = manager.activate(output_b, formatter)

    manager.deactivate(lease_a)

    expect(manager).to be_active

    manager.deactivate(lease_b)
    expect(manager).not_to be_active
  end

  it "rolls back proxy installation when activation fails" do
    original_stdout = $stdout
    original_stderr = $stderr
    manager = described_class.new
    manager.install!
    allow(manager.stderr_proxy).to receive(:activate!).and_raise("activation failed")

    expect { manager.activate(StringIO.new, double(:formatter)) }.to raise_error("activation failed")

    expect(manager).not_to be_active
    expect($stdout).to equal(original_stdout)
    expect($stderr).to equal(original_stderr)
    expect(manager.stdout_proxy).to be_raw_mode
    expect(manager.stderr_proxy).to be_raw_mode
  ensure
    manager&.restore!
    $stdout = original_stdout if original_stdout
    $stderr = original_stderr if original_stderr
  end

  it "does not roll back a newer activation" do
    manager = described_class.new
    original_stdout = $stdout
    original_stderr = $stderr
    token = manager.generation
    lease = manager.activate(StringIO.new, double(:formatter, finish_capture: nil))

    manager.rollback_if_unchanged(token)

    expect(manager).to be_active
    manager.deactivate(lease)
  ensure
    manager&.restore!
    $stdout = original_stdout if original_stdout
    $stderr = original_stderr if original_stderr
  end
end
