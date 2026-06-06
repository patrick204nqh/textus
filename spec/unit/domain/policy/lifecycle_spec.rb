require "spec_helper"

RSpec.describe Textus::Domain::Policy::Lifecycle do
  it "parses ttl to seconds and exposes the on_expire action" do
    p = described_class.new(ttl: "30d", on_expire: "drop")
    expect(p.ttl_seconds).to eq(30 * 86_400)
    expect(p.on_expire).to eq(:drop)
  end

  it "classifies drop/archive as destructive (sweep-only) and refresh/warn as lazy (read-safe)" do
    expect(described_class.new(ttl: "1h", on_expire: "drop").destructive?).to be(true)
    expect(described_class.new(ttl: "1h", on_expire: "archive").destructive?).to be(true)
    expect(described_class.new(ttl: "1h", on_expire: "refresh").lazy?).to be(true)
    expect(described_class.new(ttl: "1h", on_expire: "warn").lazy?).to be(true)
  end

  it "rejects an unknown on_expire action" do
    expect { described_class.new(ttl: "1h", on_expire: "nuke") }
      .to raise_error(Textus::UsageError, /lifecycle action must be one of/)
  end

  it "rejects an action outside the allowed set passed by the caller (ADR 0091)" do
    expect { Textus::Domain::Policy::Lifecycle.new(ttl: "30m", on_expire: "drop", allowed: %i[refresh warn]) }
      .to raise_error(Textus::UsageError, /must be one of refresh\|warn/)
  end
end
