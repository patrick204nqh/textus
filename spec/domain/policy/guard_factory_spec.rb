require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Domain::Policy::GuardFactory do
  def manifest_head
    <<~YAML
      version: textus/3
      zones:
        - { name: working, kind: origin }
        - { name: identity, kind: origin }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, kind: leaf }
        - { key: identity.x, path: identity/x.md, zone: identity, kind: leaf }
      rules:
    YAML
  end

  def with_factory(rules_yaml)
    Dir.mktmpdir do |root|
      dir = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(dir, "zones", "working"))
      FileUtils.mkdir_p(File.join(dir, "zones", "identity"))
      File.write(File.join(dir, "manifest.yaml"), manifest_head + rules_yaml)
      store = Textus::Store.new(dir)
      yield described_class.new(manifest: store.manifest, schemas: store.schemas)
    end
  end

  it "builds base ++ composed for a transition+key" do
    with_factory(<<~RULES) do |factory|
      - match: "working.**"
        guard: { accept: [{ fresh_within: "1h" }] }
    RULES
      guard = factory.for(:accept, "working.notes")
      names = guard.predicates.map(&:name)
      expect(names.first).to eq("accept_signed")  # base for :accept
      expect(names).to include("fresh_within")    # composed from rules
    end
  end

  it "returns base-only guard when no rule matches" do
    with_factory("  []\n") do |factory|
      guard = factory.for(:put, "identity.x")
      expect(guard.predicates.map(&:name)).to eq(["zone_writable_by"])
    end
  end

  it "dedupes by name when base and composed overlap (first wins)" do
    with_factory(<<~RULES) do |factory|
      - match: "working.**"
        guard: { accept: [accept_signed, schema_valid] }
    RULES
      names = factory.for(:accept, "working.notes").predicates.map(&:name)
      expect(names).to eq(%w[accept_signed schema_valid])
    end
  end
end
