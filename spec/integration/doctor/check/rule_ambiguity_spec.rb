require "spec_helper"

RSpec.describe Textus::Doctor::Check::RuleAmbiguity do
  def with_store(manifest_yaml, extra_zones: [])
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "knowledge"))
      extra_zones.each { |z| FileUtils.mkdir_p(File.join(textus, "zones", z)) }
      File.write(File.join(textus, "manifest.yaml"), manifest_yaml)
      yield Textus::Store.new(textus)
    end
  end

  it "returns no issues when each slot has a single winner" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, zone: knowledge, kind: leaf}

      rules:
        - match: knowledge.foo
          upkeep: { ttl: 10m, action: warn }
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store.container).call).to eq([])
    end
  end

  it "warns when two rules of equal specificity carry the same slot" do
    # Both globs (`knowledge.*` and `*.foo`) have specificity 11 (10 literal + 1 wildcard).
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, zone: knowledge, kind: leaf}

      rules:
        - match: knowledge.*
          upkeep: { ttl: 10m, action: warn }
        - match: "*.foo"
          upkeep: { ttl: 1h, action: warn }
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store.container).call
      ambig = issues.find { |i| i["code"] == "rule.ambiguity" }
      expect(ambig).not_to be_nil
      expect(ambig["subject"]).to eq("knowledge.foo")
      expect(ambig["level"]).to eq("warning")
      expect(ambig["message"]).to include("upkeep")
    end
  end

  it "warns on an upkeep strategy tie (source_change ambiguity; ADR 0090/0091)" do
    # Two equally-specific rules both assign a `strategy:` upkeep to the same derived entry.
    manifest = <<~YAML
      version: textus/3
      roles: [{ name: automation, can: [reconcile] }, { name: human, can: [author] }]
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.src, path: knowledge/src.md, zone: knowledge, kind: leaf }
        - { key: artifacts.foo, path: artifacts/foo.json, zone: artifacts,
            kind: derived, format: json, compute: { kind: projection, select: ["knowledge.*"] } }
      rules:
        - match: artifacts.*
          upkeep: { strategy: sync }
        - match: "*.foo"
          upkeep: { strategy: async }
    YAML

    with_store(manifest, extra_zones: ["artifacts"]) do |store|
      issues = described_class.new(store.container).call
      ambig = issues.find { |i| i["code"] == "rule.ambiguity" && i["message"].include?("upkeep") }
      expect(ambig).not_to be_nil
      expect(ambig["subject"]).to eq("artifacts.foo")
    end
  end

  it "does not warn when one block dominates by specificity" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, zone: knowledge, kind: leaf}

      rules:
        - match: knowledge.*
          upkeep: { ttl: 10m, action: warn }
        - match: knowledge.foo
          upkeep: { ttl: 1h, action: warn }
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store.container).call).to eq([])
    end
  end
end
