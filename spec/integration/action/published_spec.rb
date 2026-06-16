require "spec_helper"

RSpec.describe Textus::Action::Published do
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
            source: { from: external, command: "make", sources: [] }
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
