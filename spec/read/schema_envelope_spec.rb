require "spec_helper"

RSpec.describe Textus::Read::SchemaEnvelope do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge],
      schemas: {
        "person" => <<~YAML,
          name: person
          fields:
            full_name: { type: string, maintained_by: human }
        YAML
      },
      files: {
        "zones/knowledge/person.md" => "---\nfull_name: Alice\n---\nbody\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.person, path: knowledge/person.md, zone: knowledge, schema: person, kind: leaf}

      YAML
    )
  end

  it "returns a hash with key, schema_ref, and schema as a Hash for a declared schema" do
    ops = store.as("human")
    result = ops.schema("knowledge.person")

    expect(result).to include(
      "key" => "knowledge.person",
      "schema_ref" => "person",
      "schema" => be_a(Hash),
    )
    expect(result["schema"]).to include("name" => "person")
  end
end
