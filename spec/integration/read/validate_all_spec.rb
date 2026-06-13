require "spec_helper"

RSpec.describe Textus::Read::ValidateAll do
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
          - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

      YAML
    )
  end

  it "returns a Hash with key ok" do
    ops = store.as("human")
    result = ops.validate_all
    expect(result).to be_a(Hash)
    expect(result).to have_key("ok")
  end
end
