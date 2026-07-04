RSpec.describe Textus::Protocol::Session::Context do
  it "is a Data.define with expected fields" do
    ctx = described_class.new(
      role: "agent",
      correlation_id: "abc-123",
      dry_run: false,
      cursor: 42,
      contract_etag: "sha256:a1b2",
      propose_lane: nil
    )
    expect(ctx.role).to eq("agent")
    expect(ctx.cursor).to eq(42)
    expect(ctx.dry_run).to be(false)
  end

  it "builds a Call object via #call" do
    ctx = described_class.new(
      role: "agent", correlation_id: "abc-123",
      dry_run: false, cursor: 0, contract_etag: "x", propose_lane: nil
    )
    call = ctx.call
    expect(call).to be_a(Textus::Value::Call)
    expect(call.role).to eq("agent")
    expect(call.correlation_id).to eq("abc-123")
  end

  it "supports with() for immutable updates" do
    ctx = described_class.new(
      role: "agent", correlation_id: "abc-123",
      dry_run: false, cursor: 0, contract_etag: "x", propose_lane: nil
    )
    updated = ctx.with(cursor: 99)
    expect(ctx.cursor).to eq(0)
    expect(updated.cursor).to eq(99)
  end
end
