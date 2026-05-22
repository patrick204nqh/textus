require "spec_helper"

RSpec.describe Textus::Domain::Policy::Refresh do
  it "exposes ttl_seconds parsed from 6h shorthand" do
    p = described_class.new(ttl: "6h", on_stale: :sync, sync_budget_ms: nil)
    expect(p.ttl_seconds).to eq(6 * 3600)
  end

  it "accepts bare integers" do
    expect(described_class.new(ttl: "300", on_stale: :warn, sync_budget_ms: nil).ttl_seconds).to eq(300)
  end

  it "returns nil ttl_seconds when ttl is unparseable" do
    expect(described_class.new(ttl: "soon", on_stale: :warn, sync_budget_ms: nil).ttl_seconds).to be_nil
  end

  it "rejects unknown on_stale values" do
    expect do
      described_class.new(ttl: "1h", on_stale: :explode, sync_budget_ms: nil)
    end.to raise_error(Textus::UsageError, /on_stale.*one of/)
  end

  it "exports a Domain::Freshness::Policy view" do
    p = described_class.new(ttl: "1h", on_stale: :warn, sync_budget_ms: 500)
    fp = p.to_freshness_policy
    expect(fp).to be_a(Textus::Domain::Freshness::Policy)
    expect(fp.ttl_seconds).to eq(3600)
    expect(fp.on_stale).to eq(:warn)
    expect(fp.sync_budget_ms).to eq(500)
  end
end
