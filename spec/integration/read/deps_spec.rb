require "spec_helper"

RSpec.describe Textus::Read::Deps do
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
            path: artifacts/catalogs/people.md
            zone: artifacts
            owner: automation:auto
            source: { from: template, template: people.mustache, project: { select: knowledge.people } }
      YAML
    )
  end

  it "returns the structured deps for a derived entry (ADR 0060 amendment)" do
    ops = store.as("human")
    result = ops.deps("artifacts.catalogs.people")
    expect(result["key"]).to eq("artifacts.catalogs.people")
    expect(result["deps"]).to include("knowledge.people")
  end
end
