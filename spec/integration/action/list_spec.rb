require "spec_helper"

RSpec.describe Textus::Action::List do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge notes],
      files: {
        "data/knowledge/alpha.md" => "---\nname: alpha\n---\nbody\n",
        "data/knowledge/beta.md" => "---\nname: beta\n---\nbody\n",
        "data/notes/report.md" => "---\nname: report\n---\nbody\n",
      },
      manifest: <<~YAML,
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
          - { name: notes,   kind: canon }
        entries:
          - { key: knowledge.alpha, path: knowledge/alpha.md, lane: knowledge, kind: leaf}

          - { key: knowledge.beta,  path: knowledge/beta.md,  lane: knowledge, kind: leaf}

          - { key: notes.report,  path: notes/report.md,  lane: notes, kind: leaf}

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
    rows = ops.list(lane: "notes")
    expect(rows.map { |r| r["key"] }).to eq(["notes.report"])
  end
end
