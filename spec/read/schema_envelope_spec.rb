require "spec_helper"

RSpec.describe Textus::Read::SchemaEnvelope do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[working],
      schemas: {
        "person" => <<~YAML,
          name: person
          fields:
            full_name: { type: string, maintained_by: human }
        YAML
      },
      files: {
        "zones/working/person.md" => "---\nfull_name: Alice\n---\nbody\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: working, kind: canon }
        entries:
          - { key: working.person, path: working/person.md, zone: working, schema: person, kind: leaf}

      YAML
    )
  end

  it "returns a hash with key, schema_ref, and schema as a Hash for a declared schema" do
    ops = store.as("human")
    result = ops.schema_envelope("working.person")

    expect(result).to include(
      "key" => "working.person",
      "schema_ref" => "person",
      "schema" => be_a(Hash),
    )
    expect(result["schema"]).to include("name" => "person")
  end
end
