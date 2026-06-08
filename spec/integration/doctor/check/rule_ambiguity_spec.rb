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
          retention: { ttl: 10m, action: drop }
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
          retention: { ttl: 10m, action: drop }
        - match: "*.foo"
          retention: { ttl: 1h, action: archive }
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store.container).call
      ambig = issues.find { |i| i["code"] == "rule.ambiguity" }
      expect(ambig).not_to be_nil
      expect(ambig["subject"]).to eq("knowledge.foo")
      expect(ambig["level"]).to eq("warning")
      expect(ambig["message"]).to include("retention")
    end
  end

  it "warns on a retention tie across equally-specific rules (ADR 0093)" do
    # Two equally-specific rules both assign retention to the same intake entry.
    manifest = <<~YAML
      version: textus/3
      roles: [{ name: automation, can: [converge] }, { name: human, can: [author] }]
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.src, path: knowledge/src.md, zone: knowledge, kind: leaf }
        - { key: artifacts.foo, path: artifacts/foo.json, zone: artifacts,
            kind: produced, source: { from: handler, handler: noop } }
      rules:
        - match: artifacts.*
          retention: { ttl: 1d, action: drop }
        - match: "*.foo"
          retention: { ttl: 2d, action: archive }
    YAML

    with_store(manifest, extra_zones: ["artifacts"]) do |store|
      issues = described_class.new(store.container).call
      ambig = issues.find { |i| i["code"] == "rule.ambiguity" && i["message"].include?("retention") }
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
          retention: { ttl: 10m, action: drop }
        - match: knowledge.foo
          retention: { ttl: 1h, action: archive }
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store.container).call).to eq([])
    end
  end
end
