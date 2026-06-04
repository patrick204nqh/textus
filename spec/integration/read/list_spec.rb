require "spec_helper"

RSpec.describe Textus::Read::List do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge notes],
      files: {
        "zones/knowledge/alpha.md" => "---\nname: alpha\n---\nbody\n",
        "zones/knowledge/beta.md" => "---\nname: beta\n---\nbody\n",
        "zones/notes/report.md" => "---\nname: report\n---\nbody\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: notes,   kind: canon }
        entries:
          - { key: knowledge.alpha, path: knowledge/alpha.md, zone: knowledge, kind: leaf}

          - { key: knowledge.beta,  path: knowledge/beta.md,  zone: knowledge, kind: leaf}

          - { key: notes.report,  path: notes/report.md,  zone: notes, kind: leaf}

      YAML
    )
  end

  it "returns all entries when called with no filters" do
    ops = store.as("human")
    rows = ops.list
    expect(rows.map { |r| r["key"] }).to contain_exactly(
      "knowledge.alpha", "knowledge.beta", "notes.report"
    )
  end

  it "filters by prefix" do
    ops = store.as("human")
    rows = ops.list(prefix: "knowledge")
    expect(rows.map { |r| r["key"] }).to contain_exactly("knowledge.alpha", "knowledge.beta")
  end

  it "filters by zone" do
    ops = store.as("human")
    rows = ops.list(zone: "notes")
    expect(rows.map { |r| r["key"] }).to eq(["notes.report"])
  end
end
