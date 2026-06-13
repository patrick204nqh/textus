require "spec_helper"

RSpec.describe Textus::Read::Where do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge],
      files: { "data/knowledge/doc.md" => "---\nname: doc\n---\nbody\n" },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, owner: human:alice, kind: leaf}

      YAML
    )
  end

  it "returns a hash with protocol, key, zone, owner, path for a known key" do
    ops = store.as("human")
    result = ops.where("knowledge.doc")

    expect(result).to include(
      "protocol" => be_a(String),
      "key" => "knowledge.doc",
      "zone" => "knowledge",
      "owner" => "human:alice",
      "path" => end_with("knowledge/doc.md"),
    )
  end
end
