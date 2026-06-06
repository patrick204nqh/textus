require "spec_helper"

RSpec.describe "ADR 0091 upkeep<->entry-kind load validation" do
  include_context "textus_store_fixture"

  def load_manifest(entries_yaml, rules_yaml)
    store_from_manifest(root, zones: %w[artifacts knowledge], manifest: <<~YAML)
      version: textus/3
      roles: [{ name: automation, can: [reconcile] }, { name: human, can: [author] }]
      zones:
        - { name: artifacts, kind: machine }
        - { name: knowledge, kind: canon }
      entries:
      #{entries_yaml}
      rules:
      #{rules_yaml}
    YAML
  end

  it "rejects a dependency upkeep (strategy) on a non-derived (intake) entry" do
    entry = "  - { key: artifacts.feeds.cal, path: feeds/cal.json, zone: artifacts, " \
            "kind: intake, intake: { handler: noop } }"
    rule  = "  - { match: artifacts.feeds.**, upkeep: { strategy: sync } }"
    expect do
      load_manifest(entry, rule)
    end.to raise_error(Textus::BadManifest, /strategy.*only valid for a derived entry/)
  end

  it "rejects a refresh action on a stored (canon) entry" do
    entry = "  - { key: knowledge.doc, path: doc.md, zone: knowledge, kind: leaf }"
    rule  = "  - { match: knowledge.**, upkeep: { ttl: 30m, action: refresh } }"
    expect do
      load_manifest(entry, rule)
    end.to raise_error(Textus::BadManifest, /refresh is only valid for an intake entry/)
  end

  it "rejects a destructive action on a derived entry" do
    entry = "  - { key: artifacts.derived.idx, path: idx.json, zone: artifacts, " \
            "kind: derived, format: json, compute: { kind: projection, select: [\"x.*\"] } }"
    rule  = "  - { match: artifacts.derived.**, upkeep: { ttl: 1d, action: drop } }"
    expect do
      load_manifest(entry, rule)
    end.to raise_error(Textus::BadManifest, /derived entry regenerates/)
  end

  it "accepts the matching grammars" do
    entries = <<~ENTRIES
      - { key: artifacts.feeds.cal, path: feeds/cal.json, zone: artifacts,
          kind: intake, intake: { handler: noop } }
      - { key: artifacts.derived.idx, path: idx.json, zone: artifacts,
          kind: derived, format: json, compute: { kind: projection, select: ["x.*"] } }
    ENTRIES
    rules = <<~RULES
      - { match: artifacts.feeds.**, upkeep: { ttl: 30m, action: refresh } }
      - { match: artifacts.derived.**, upkeep: { strategy: async } }
    RULES
    expect do
      load_manifest(entries, rules)
    end.not_to raise_error
  end
end
