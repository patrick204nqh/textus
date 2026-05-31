require "spec_helper"

RSpec.describe Textus::Read::Uid do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[working],
      files: {
        "zones/working/doc.md" => <<~MD,
          ---
          uid: "abc123def456"
          name: doc
          ---
          body
        MD
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: working, kind: canon }
        entries:
          - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

      YAML
    )
  end

  it "returns the uid declared in the entry frontmatter" do
    ops = store.as("human")
    result = ops.uid("working.doc")
    expect(result).to eq("abc123def456")
  end
end
