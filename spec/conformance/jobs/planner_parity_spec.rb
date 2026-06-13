require "spec_helper"

RSpec.describe Textus::Jobs::Planner do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root, zones: %w[knowledge feeds],
            manifest: <<~YAML,
              version: textus/3
              zones:
                - { name: knowledge, kind: canon }
                - { name: feeds, kind: machine }
              entries:
                - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }
                - key: feeds.catalog
                  kind: produced
                  path: feeds/catalog.json
                  zone: feeds
                  source: { from: project, select: "knowledge", pluck: [title] }
                  publish:
                    - { to: CATALOG.md, template: catalog.mustache }
                - key: feeds.doc
                  kind: produced
                  path: feeds/doc.md
                  zone: feeds
                  source: { from: handler, handler: demo, ttl: 1s }
            YAML
            files: {
              "data/knowledge/a.md" => "---\ntitle: Apple\n---\nx\n",
              "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
              "steps/fetch/demo.rb" => <<~RUBY,
                class DemoFetch < Textus::Step::Fetch
                  def call(config:, args:, **)
                    _ = config
                    _ = args
                    { _meta: {}, body: "x" }
                  end
                end
              RUBY
            }
    )
  end

  it "plans equivalent work for manual kick and schedule tick" do
    planner = described_class.new(container: store.container)

    manual = planner.plan(triggers: [{ "type" => "manual.kick" }], scope: { "prefix" => nil, "zone" => nil }, role: "automation")
    tick = planner.plan(triggers: [{ "type" => "schedule.tick" }], scope: { "prefix" => nil, "zone" => nil }, role: "automation")

    expect(manual.map(&:id).sort).to eq(tick.map(&:id).sort)
  end
end
