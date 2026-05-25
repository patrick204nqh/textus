require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::PolicyAmbiguity do
  def with_store(manifest_yaml)
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      File.write(File.join(textus, "manifest.yaml"), manifest_yaml)
      yield Textus::Store.new(textus)
    end
  end

  it "returns no issues when each slot has a single winner" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working }
      policies:
        - match: working.foo
          refresh: { ttl: 10m }
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store).call).to eq([])
    end
  end

  it "warns when two policies of equal specificity carry the same slot" do
    # Both globs (`working.*` and `*.foo`) have specificity 11 (10 literal + 1 wildcard).
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working }
      policies:
        - match: working.*
          refresh: { ttl: 10m }
        - match: "*.foo"
          refresh: { ttl: 1h }
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store).call
      ambig = issues.find { |i| i["code"] == "policy.ambiguity" }
      expect(ambig).not_to be_nil
      expect(ambig["subject"]).to eq("working.foo")
      expect(ambig["level"]).to eq("warning")
      expect(ambig["message"]).to include("refresh")
    end
  end

  it "does not warn when one block dominates by specificity" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working }
      policies:
        - match: working.*
          refresh: { ttl: 10m }
        - match: working.foo
          refresh: { ttl: 1h }
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store).call).to eq([])
    end
  end
end
