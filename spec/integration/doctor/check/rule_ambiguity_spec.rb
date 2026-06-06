require "spec_helper"

RSpec.describe Textus::Doctor::Check::RuleAmbiguity do
  def with_store(manifest_yaml)
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "knowledge"))
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
          upkeep: { "on": stale, ttl: 10m, action: warn }
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
          upkeep: { "on": stale, ttl: 10m, action: warn }
        - match: "*.foo"
          upkeep: { "on": stale, ttl: 1h, action: warn }
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

  it "warns on an upkeep source_change tie (materialize folded into upkeep; ADR 0090)" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, zone: knowledge, kind: leaf}
      rules:
        - match: knowledge.*
          upkeep: { "on": source_change, strategy: sync }
        - match: "*.foo"
          upkeep: { "on": source_change, strategy: async }
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store.container).call
      ambig = issues.find { |i| i["code"] == "rule.ambiguity" && i["message"].include?("upkeep") }
      expect(ambig).not_to be_nil
      expect(ambig["subject"]).to eq("knowledge.foo")
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
          upkeep: { "on": stale, ttl: 10m, action: warn }
        - match: knowledge.foo
          upkeep: { "on": stale, ttl: 1h, action: warn }
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store.container).call).to eq([])
    end
  end
end
