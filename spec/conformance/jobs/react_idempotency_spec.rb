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
                - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
                - key: feeds.catalog
                  kind: produced
                  path: data/feeds/catalog.json
                  lane: feeds
                  source: { from: derive, select: "knowledge", pluck: [title] }
                  publish:
                    - { to: CATALOG.md, template: catalog.mustache }
            YAML
            files: {
              "data/knowledge/a.md" => "---\ntitle: Apple\n---\nx\n",
              "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
            }
    )
  end

  it "coalesces duplicate entry.written triggers into one effective decorate set" do
    planner = Textus::Jobs::Planner.new(container: store.container)
    jobs = planner.plan(
      triggers: [{ "type" => "entry.written" }, { "type" => "entry.written" }],
      scope: { "prefix" => nil, "lane" => nil },
      role: "automation",
    )

    ids = jobs.map(&:id)
    decorate_ids = ids.select { |id| id.start_with?("decorate:") }
    expect(decorate_ids.uniq).to eq(decorate_ids)
  end
end
