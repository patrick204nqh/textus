require "spec_helper"

RSpec.describe Textus::Read::Stale do
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
          - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

      YAML
    )
  end

  it "returns an Array" do
    ops = store.as("human")
    result = ops.stale
    expect(result).to be_an(Array)
  end
end
