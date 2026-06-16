require "spec_helper"

RSpec.describe "jobs react idempotency" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root, lanes: %w[knowledge feeds],
            manifest: <<~YAML,
              version: textus/3
              lanes:
                - { name: knowledge, kind: canon }
                - { name: feeds, kind: machine }
              entries:
                - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
                - key: feeds.catalog
                  kind: produced
                  path: feeds/catalog.json
                  lane: feeds
                  source: { from: external, command: "make", sources: [] }
                  publish:
                    - { to: CATALOG.md, template: catalog.mustache }
            YAML
            files: {
              "data/knowledge/a.md" => "---\ntitle: Apple\n---\nx\n",
              "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
            }
    )
  end

  it "coalesces duplicate entry.written triggers into one effective job set" do
    planner = Textus::Jobs::Planner.new(container: store.container)
    jobs = planner.plan(
      trigger: { "type" => "entry.written" },
      role: "automation",
    )

    expect(jobs.map(&:type)).to include("materialize")
    ids = jobs.map(&:id)
    expect(ids.uniq).to eq(ids)
  end
end
