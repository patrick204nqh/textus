require "spec_helper"

RSpec.describe Textus::Read::List do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[working notes],
      files: {
        "zones/working/alpha.md" => "---\nname: alpha\n---\nbody\n",
        "zones/working/beta.md" => "---\nname: beta\n---\nbody\n",
        "zones/notes/report.md" => "---\nname: report\n---\nbody\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: working, kind: canon }
          - { name: notes,   kind: canon }
        entries:
          - { key: working.alpha, path: working/alpha.md, zone: working, kind: leaf}

          - { key: working.beta,  path: working/beta.md,  zone: working, kind: leaf}

          - { key: notes.report,  path: notes/report.md,  zone: notes, kind: leaf}

      YAML
    )
  end

  it "returns all entries when called with no filters" do
    ops = store.as("human")
    rows = ops.list
    expect(rows.map { |r| r["key"] }).to contain_exactly(
      "working.alpha", "working.beta", "notes.report"
    )
  end

  it "filters by prefix" do
    ops = store.as("human")
    rows = ops.list(prefix: "working")
    expect(rows.map { |r| r["key"] }).to contain_exactly("working.alpha", "working.beta")
  end

  it "filters by zone" do
    ops = store.as("human")
    rows = ops.list(zone: "notes")
    expect(rows.map { |r| r["key"] }).to eq(["notes.report"])
  end
end
