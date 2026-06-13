require "spec_helper"

RSpec.describe Textus::Manifest::Policy::Retention do
  it "parses ttl + a destructive action" do
    r = described_class.new("ttl" => "90d", "action" => "archive")
    expect(r.action).to eq(:archive)
    expect(r.ttl_seconds).to eq(90 * 24 * 3600)
    expect(r.destructive?).to be(true)
  end

  it "accepts drop" do
    expect(described_class.new("ttl" => "30d", "action" => "drop").action).to eq(:drop)
  end

  it "rejects a non-destructive action (warn/refresh are gone in ADR 0093)" do
    expect { described_class.new("ttl" => "1d", "action" => "warn") }
      .to raise_error(Textus::BadManifest, /action must be one of drop\|archive/)
  end

  it "rejects refresh too" do
    expect { described_class.new("ttl" => "1d", "action" => "refresh") }
      .to raise_error(Textus::BadManifest, /action must be one of drop\|archive/)
  end

  it "rejects a missing ttl" do
    expect { described_class.new("action" => "drop") }
      .to raise_error(Textus::BadManifest, /ttl/)
  end

  it "rejects a missing action" do
    expect { described_class.new("ttl" => "1d") }
      .to raise_error(Textus::BadManifest, /action must be one of drop\|archive/)
  end
end
