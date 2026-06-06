require "spec_helper"

RSpec.describe Textus::Manifest::Schema do
  def validate!(rules)
    described_class.validate!(
      "version" => "textus/3",
      "zones" => [{ "name" => "feeds", "kind" => "quarantine" }],
      "entries" => [],
      "rules" => rules,
    )
  end

  it "accepts an upkeep stale block with ttl + action" do
    expect do
      validate!([{ "match" => "feeds.*", "upkeep" => { "on" => "stale", "ttl" => "1h", "action" => "refresh" } }])
    end.not_to raise_error
  end

  it "rejects an unknown key inside upkeep" do
    expect do
      validate!([{ "match" => "feeds.*", "upkeep" => { "on" => "stale", "ttl" => "1h", "bogus" => 1 } }])
    end.to raise_error(Textus::BadManifest, /unknown key 'bogus' at '\$\.rules\[0\]\.upkeep'/)
  end

  # ADR 0090 folded the retired `lifecycle:`/`materialize:` rule slots into the
  # single `upkeep` tagged union; the schema rejects the old keys with a hint.
  it "rejects a retired lifecycle block, pointing at upkeep" do
    expect do
      validate!([{ "match" => "feeds.*", "lifecycle" => { "ttl" => "1h", "on_expire" => "refresh" } }])
    end.to raise_error(Textus::BadManifest, /`lifecycle:` was merged into `upkeep`/)
  end

  it "rejects a retired materialize block, pointing at upkeep" do
    expect do
      validate!([{ "match" => "artifacts.*", "materialize" => { "on_change" => "sync" } }])
    end.to raise_error(Textus::BadManifest, /`materialize:` was merged into `upkeep`/)
  end
end
