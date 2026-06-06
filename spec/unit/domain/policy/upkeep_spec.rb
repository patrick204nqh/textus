require "spec_helper"

RSpec.describe Textus::Domain::Policy::Upkeep do
  describe "age-based (ttl/action keys)" do
    let(:policy) { described_class.new("ttl" => "6h", "action" => "refresh") }

    it "is the stale tag and exposes a Lifecycle sub-view" do
      expect(policy.stale?).to be(true)
      expect(policy.source_change?).to be(false)
      expect(policy.lifecycle).to be_a(Textus::Domain::Policy::Lifecycle)
      expect(policy.lifecycle.ttl_seconds).to eq(6 * 3600)
      expect(policy.lifecycle.on_expire).to eq(:refresh)
      expect(policy.materialize).to be_nil
    end

    it "rejects mixing age and dependency keys" do
      expect { described_class.new("ttl" => "6h", "action" => "refresh", "strategy" => "sync") }
        .to raise_error(Textus::BadManifest, /cannot mix/)
    end

    it "rejects an unknown action via the inner Lifecycle" do
      expect { described_class.new("ttl" => "6h", "action" => "explode") }
        .to raise_error(Textus::Error, /refresh|warn|drop|archive/)
    end
  end

  describe "dependency-based (strategy key)" do
    let(:policy) { described_class.new("strategy" => "sync") }

    it "is the source_change tag and exposes a Materialize sub-view" do
      expect(policy.source_change?).to be(true)
      expect(policy.materialize).to be_a(Textus::Domain::Policy::Materialize)
      expect(policy.materialize.sync?).to be(true)
      expect(policy.lifecycle).to be_nil
    end

    it "defaults strategy to async when strategy key is nil" do
      expect(described_class.new("strategy" => nil).materialize.on_change).to eq("async")
    end
  end

  it "rejects an empty block (no recognisable keys)" do
    expect { described_class.new({}) }
      .to raise_error(Textus::BadManifest, /must carry/)
  end

  describe "ADR 0091 keyed upkeep (no on:)" do
    it "reads the age grammar from ttl/action keys" do
      u = Textus::Domain::Policy::Upkeep.new({ "ttl" => "30m", "action" => "refresh" })
      expect(u.lifecycle.on_expire).to eq(:refresh)
      expect(u.materialize).to be_nil
      expect(u.stale?).to be(true)
    end

    it "reads the dependency grammar from strategy" do
      u = Textus::Domain::Policy::Upkeep.new({ "strategy" => "sync" })
      expect(u.materialize.sync?).to be(true)
      expect(u.lifecycle).to be_nil
      expect(u.source_change?).to be(true)
    end

    it "rejects mixing the two grammars" do
      expect { Textus::Domain::Policy::Upkeep.new({ "ttl" => "30m", "strategy" => "sync" }) }
        .to raise_error(Textus::BadManifest, /cannot mix/)
    end

    it "rejects an empty/ambiguous block" do
      expect { Textus::Domain::Policy::Upkeep.new({}) }
        .to raise_error(Textus::BadManifest, /must carry/)
    end
  end
end
