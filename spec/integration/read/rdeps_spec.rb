require "spec_helper"

RSpec.describe Textus::Read::Rdeps do
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
          - { name: artifacts, kind: derived }
        entries:
          - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested}

          - key: artifacts.catalogs.people
            kind: derived
            path: artifacts/catalogs/people.md
            zone: artifacts
            owner: automation:auto
            compute: { kind: projection, select: knowledge.people }
            template: people.mustache
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
