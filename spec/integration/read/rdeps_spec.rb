require "spec_helper"

RSpec.describe Textus::Read::Rdeps do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge artifacts],
      files: {
        "templates/people.mustache" => "{{#entries}}- {{name}}\n{{/entries}}",
        "data/knowledge/people/alice.md" => "---\nname: alice\n---\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested}

          - key: artifacts.catalogs.people
            kind: produced
            path: artifacts/catalogs/people.json
            zone: artifacts
            owner: automation:auto
            source: { from: project, select: knowledge.people }
            publish:
              - { to: PEOPLE.md, template: people.mustache }
      YAML
    )
  end

  it "returns the structured dependents of a key (ADR 0060 amendment)" do
    ops = store.as("human")
    result = ops.rdeps("knowledge.people")
    expect(result["key"]).to eq("knowledge.people")
    expect(result["rdeps"]).to include("artifacts.catalogs.people")
  end
end
