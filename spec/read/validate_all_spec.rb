require "spec_helper"

RSpec.describe Textus::Read::ValidateAll do
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

  it "returns a Hash with key ok" do
    ops = store.as("human")
    result = ops.validate_all
    expect(result).to be_a(Hash)
    expect(result).to have_key("ok")
  end
end
