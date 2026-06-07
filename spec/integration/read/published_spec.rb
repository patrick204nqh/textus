require "spec_helper"

RSpec.describe Textus::Read::Published do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge artifacts],
      files: {
        "templates/people.mustache" => "{{#entries}}- {{name}}\n{{/entries}}",
        "zones/knowledge/people/alice.md" => "---\nname: alice\n---\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested}

          - key: artifacts.catalogs.people
            kind: derived
            path: artifacts/catalogs/people.json
            zone: artifacts
            owner: automation:auto
            source: { from: project, select: knowledge.people }
            publish:
              - { to: PEOPLE.md, template: people.mustache }
      YAML
    )
  end

  it "returns entries that have publish_to, including artifacts.catalogs.people" do
    ops = store.as("human")
    result = ops.published
    expect(result.map { |r| r["key"] }).to include("artifacts.catalogs.people")
  end
end
