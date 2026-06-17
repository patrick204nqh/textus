require "spec_helper"

RSpec.describe Textus::Action::Published do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge artifacts],
      files: {
        "templates/people.erb" => "<% entries.each do |e| %>- <%= e[\"name\"] %>\n<% end -%>",
        "data/knowledge/people/alice.md" => "---\nname: alice\n---\n",
      },
      manifest: <<~YAML,
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - { key: knowledge.people, path: knowledge/people, lane: knowledge, owner: human:self, kind: nested}

          - key: artifacts.catalogs.people
            kind: produced
            path: artifacts/catalogs/people.json
            lane: artifacts
            owner: automation:auto
            source: { from: external, command: "make", sources: [] }
            publish:
              - { to: PEOPLE.md, template: people.erb }
      YAML
    )
  end

  it "returns entries that have publish_to, including artifacts.catalogs.people" do
    ops = store.as("human")
    result = ops.published
    expect(result.map { |r| r["key"] }).to include("artifacts.catalogs.people")
  end
end
