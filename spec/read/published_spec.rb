require "spec_helper"

RSpec.describe Textus::Read::Published do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[working output],
      files: {
        "templates/people.mustache" => "{{#entries}}- {{name}}\n{{/entries}}",
        "zones/working/people/alice.md" => "---\nname: alice\n---\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: working, kind: canon }
          - { name: output, kind: derived }
        entries:
          - { key: working.people, path: working/people, zone: working, schema: null, owner: human:o, nested: true, kind: nested}

          - key: output.catalogs.people
            kind: derived
            path: output/catalogs/people.md
            zone: output
            schema: null
            owner: automation:auto
            compute: { kind: projection, select: working.people }
            template: people.mustache
            publish_to: [PEOPLE.md]
      YAML
    )
  end

  it "returns entries that have publish_to, including output.catalogs.people" do
    ops = store.as("human")
    result = ops.published
    expect(result.map { |r| r["key"] }).to include("output.catalogs.people")
  end
end
