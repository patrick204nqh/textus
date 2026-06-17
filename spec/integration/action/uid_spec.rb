require "spec_helper"

RSpec.describe Textus::Action::Uid do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge],
      files: {
        "data/knowledge/doc.md" => <<~MD,
          ---
          uid: "abc123def456"
          name: doc
          ---
          body
        MD
      },
      manifest: <<~YAML,
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, lane: knowledge, kind: leaf}

      YAML
    )
  end

  it "returns the uid declared in the entry frontmatter" do
    ops = store.as("human")
    result = ops.uid("knowledge.doc")
    expect(result).to eq("abc123def456")
  end
end
