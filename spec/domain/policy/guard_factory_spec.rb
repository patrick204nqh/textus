require "spec_helper"

RSpec.describe Textus::Domain::Policy::GuardFactory do
  include_context "textus_store_fixture"

  def factory_for(rules_yaml)
    store = store_from_manifest(root, zones: %w[working identity], manifest: <<~YAML + rules_yaml)
      version: textus/3
      zones:
        - { name: working, kind: canon }
        - { name: identity, kind: canon }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, kind: leaf }
        - { key: identity.x, path: identity/x.md, zone: identity, kind: leaf }
      rules:
    YAML
    described_class.new(manifest: store.manifest, schemas: store.schemas)
  end

  it "builds base ++ composed for a transition+key" do
    factory = factory_for(<<~RULES)
      - match: "working.**"
        guard: { accept: [{ fresh_within: "1h" }] }
    RULES
    names = factory.for(:accept, "working.notes").predicates.map(&:name)
    expect(names.first).to eq("author_held") # base for :accept
    expect(names).to include("fresh_within") # composed from rules
  end

  it "returns base-only guard when no rule matches" do
    factory = factory_for("  []\n")
    guard = factory.for(:put, "identity.x")
    expect(guard.predicates.map(&:name)).to eq(["zone_writable_by"])
  end

  it "dedupes by name when base and composed overlap (first wins)" do
    factory = factory_for(<<~RULES)
      - match: "working.**"
        guard: { accept: [author_held, schema_valid] }
    RULES
    names = factory.for(:accept, "working.notes").predicates.map(&:name)
    expect(names).to eq(%w[author_held schema_valid])
  end
end
