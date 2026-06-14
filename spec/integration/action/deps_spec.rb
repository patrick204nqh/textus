require "spec_helper"

RSpec.describe Textus::Action::Deps do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge artifacts],
      files: {
        "templates/people.mustache" => "{{#entries}}- {{name}}\n{{/entries}}",
        "data/knowledge/people/alice.md" => "---\nname: alice\n---\n",
      },
      manifest: <<~YAML,
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - { key: knowledge.people, path: data/knowledge/people, lane: knowledge, owner: human:self, kind: nested}

          - key: artifacts.catalogs.people
            kind: produced
            path: data/artifacts/catalogs/people.json
            lane: artifacts
            owner: automation:auto
            source: { from: derive, select: knowledge.people }
            publish:
              - { to: PEOPLE.md, template: people.mustache }
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
