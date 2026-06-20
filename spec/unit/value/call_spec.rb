require "spec_helper"

RSpec.describe Textus::Value::Call do
  it "builds with defaults" do
    call = described_class.build(role: "human")
    expect(call.role).to eq("human")
    expect(call.correlation_id).to match(/\A[0-9a-f-]{36}\z/)
    expect(call.now).to be_a(Time)
    expect(call.dry_run?).to be(false)
  end

  it "is immutable; with_role returns a new instance preserving correlation_id" do
    a = described_class.build(role: "human")
    b = a.with_role("agent")
    expect(b.role).to eq("agent")
    expect(b.correlation_id).to eq(a.correlation_id)
    expect(a.role).to eq("human")
  end
end
