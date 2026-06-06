require "spec_helper"

RSpec.describe Textus::Doctor::Check::UpkeepKindMismatch do
  include_context "textus_store_fixture"

  def issues_for(manifest)
    store_from_manifest(root, zones: %w[knowledge feeds artifacts], manifest: manifest)
    described_class.new(Textus::Store.new(root).container).call
  end

  it "flags on: source_change on a non-derived (intake) entry" do
    issues = issues_for(<<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: quarantine }
      entries:
        - { key: feeds.doc, path: feeds/doc.md, zone: feeds, kind: intake, intake: { handler: h } }
      rules:
        - match: feeds.doc
          upkeep: { "on": source_change, strategy: async }
    YAML

    issue = issues.find { |i| i["code"] == "upkeep.kind_mismatch" }
    expect(issue).not_to be_nil
    expect(issue["subject"]).to eq("feeds.doc")
    expect(issue["message"]).to match(/source_change/)
  end

  it "flags age-retention (drop) on a derived entry" do
    issues = issues_for(<<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: derived }
      entries:
        - { key: knowledge.src, path: knowledge/src.md, zone: knowledge, kind: leaf }
        - { key: artifacts.out, path: artifacts/out.md, zone: artifacts, kind: derived, compute: { kind: external, command: "rake out", sources: [knowledge.src] } }
      rules:
        - match: artifacts.out
          upkeep: { "on": stale, ttl: 1h, action: drop }
    YAML

    issue = issues.find { |i| i["code"] == "upkeep.kind_mismatch" }
    expect(issue).not_to be_nil
    expect(issue["subject"]).to eq("artifacts.out")
  end

  it "passes a well-formed pairing (intake stale + derived source_change)" do
    issues = issues_for(<<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: feeds, kind: quarantine }
        - { name: artifacts, kind: derived }
      entries:
        - { key: knowledge.src, path: knowledge/src.md, zone: knowledge, kind: leaf }
        - { key: feeds.doc, path: feeds/doc.md, zone: feeds, kind: intake, intake: { handler: h } }
        - { key: artifacts.out, path: artifacts/out.md, zone: artifacts, kind: derived, compute: { kind: external, command: "rake out", sources: [knowledge.src] } }
      rules:
        - match: feeds.doc
          upkeep: { "on": stale, ttl: 6h, action: refresh }
        - match: artifacts.out
          upkeep: { "on": source_change, strategy: async }
    YAML

    expect(issues.select { |i| i["code"] == "upkeep.kind_mismatch" }).to be_empty
  end
end
