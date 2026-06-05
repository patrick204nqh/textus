require "spec_helper"

RSpec.describe Textus::Domain::Policy::Upkeep do
  describe "on: stale (age-based)" do
    let(:policy) { described_class.new("on" => "stale", "ttl" => "6h", "action" => "refresh") }

    it "is the stale tag and exposes a Lifecycle sub-view" do
      expect(policy.stale?).to be(true)
      expect(policy.source_change?).to be(false)
      expect(policy.lifecycle).to be_a(Textus::Domain::Policy::Lifecycle)
      expect(policy.lifecycle.ttl_seconds).to eq(6 * 3600)
      expect(policy.lifecycle.on_expire).to eq(:refresh)
      expect(policy.materialize).to be_nil
    end

    it "rejects a source_change-only field under stale" do
      expect { described_class.new("on" => "stale", "ttl" => "6h", "action" => "refresh", "strategy" => "sync") }
        .to raise_error(Textus::BadManifest, /strategy/)
    end

    it "rejects an unknown action via the inner Lifecycle" do
      expect { described_class.new("on" => "stale", "ttl" => "6h", "action" => "explode") }
        .to raise_error(Textus::Error, /refresh|warn|drop|archive/)
    end
  end

  describe "on: source_change (dependency-based)" do
    let(:policy) { described_class.new("on" => "source_change", "strategy" => "sync") }

    it "is the source_change tag and exposes a Materialize sub-view" do
      expect(policy.source_change?).to be(true)
      expect(policy.materialize).to be_a(Textus::Domain::Policy::Materialize)
      expect(policy.materialize.sync?).to be(true)
      expect(policy.lifecycle).to be_nil
    end

    it "defaults strategy to async when omitted" do
      expect(described_class.new("on" => "source_change").materialize.on_change).to eq("async")
    end

    it "rejects a stale-only field under source_change" do
      expect { described_class.new("on" => "source_change", "ttl" => "6h") }
        .to raise_error(Textus::BadManifest, /ttl/)
    end
  end

  it "rejects an unknown tag" do
    expect { described_class.new("on" => "whenever") }
      .to raise_error(Textus::BadManifest, /upkeep.on must be one of stale\|source_change/)
  end
end
