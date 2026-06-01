require "spec_helper"

RSpec.describe Textus::Read::Where do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[working],
      files: { "zones/working/doc.md" => "---\nname: doc\n---\nbody\n" },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: working, kind: canon }
        entries:
          - { key: working.doc, path: working/doc.md, zone: working, owner: human:alice, kind: leaf}

      YAML
    )
  end

  it "returns a hash with protocol, key, zone, owner, path for a known key" do
    ops = store.as("human")
    result = ops.where("working.doc")

    expect(result).to include(
      "protocol" => be_a(String),
      "key" => "working.doc",
      "zone" => "working",
      "owner" => "human:alice",
      "path" => end_with("working/doc.md"),
    )
  end
end
