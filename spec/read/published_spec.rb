require "spec_helper"

RSpec.describe Textus::Read::Published do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge output],
      files: {
        "templates/people.mustache" => "{{#entries}}- {{name}}\n{{/entries}}",
        "zones/knowledge/people/alice.md" => "---\nname: alice\n---\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: output, kind: derived }
        entries:
          - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested}

          - key: output.catalogs.people
            kind: derived
            path: output/catalogs/people.md
            zone: output
            owner: automation:auto
            compute: { kind: projection, select: knowledge.people }
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
