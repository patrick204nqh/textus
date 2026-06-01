require "spec_helper"

RSpec.describe Textus::Read::Stale do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge],
      files: { "zones/knowledge/doc.md" => "---\nname: doc\n---\nbody\n" },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

      YAML
    )
  end

  it "returns an Array" do
    ops = store.as("human")
    result = ops.stale
    expect(result).to be_an(Array)
  end
end
