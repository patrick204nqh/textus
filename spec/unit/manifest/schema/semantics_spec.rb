require "spec_helper"

RSpec.describe Textus::Manifest::Schema::Semantics do
  def check(raw)
    described_class.check!(raw)
  end

  it "passes a valid manifest" do
    expect { check({ "lanes" => [{ "name" => "k", "kind" => "canon" }] }) }.not_to raise_error
  end

  it "raises BadManifest for two queue lanes" do
    raw = { "lanes" => [
      { "name" => "a", "kind" => "queue" },
      { "name" => "b", "kind" => "queue" },
    ] }
    expect { check(raw) }.to raise_error(Textus::BadManifest, /at most one.*queue/)
  end

  it "raises BadManifest for two machine lanes" do
    raw = { "lanes" => [
      { "name" => "a", "kind" => "machine" },
      { "name" => "b", "kind" => "machine" },
    ] }
    expect { check(raw) }.to raise_error(Textus::BadManifest, /at most one.*machine/)
  end

  it "raises BadManifest for unknown role name" do
    raw = { "lanes" => [], "roles" => [{ "name" => "ghost", "can" => [] }] }
    expect { check(raw) }.to raise_error(Textus::BadManifest, /unknown role name/)
  end

  it "raises BadManifest for retired publish_each key with ADR hint" do
    raw = { "lanes" => [], "entries" => [{ "key" => "k", "lane" => "l", "publish_each" => true }] }
    expect { check(raw) }.to raise_error(Textus::BadManifest, /ADR 0051/)
  end

  it "raises BadManifest for invalid owner format" do
    raw = { "lanes" => [{ "name" => "k", "kind" => "canon", "owner" => "ghost:x" }], "entries" => [] }
    expect { check(raw) }.to raise_error(Textus::BadManifest, /invalid owner/)
  end
end
