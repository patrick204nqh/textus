require "spec_helper"

RSpec.describe Textus::Jobs::Planner do
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
                  source: { from: external, command: "make", sources: [] }
                  publish:
                    - { to: CATALOG.md, template: catalog.mustache }
                - key: feeds.doc
                  kind: produced
                  path: data/feeds/doc.md
                  lane: feeds
                  source: { from: external, command: "make", sources: [] }
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

  it "plans convergence work via .seed" do
    queue = Textus::Ports::JobStore.new(root: store.root)
    described_class.seed(container: store.container, queue: queue, role: "automation")
    expect(queue.ready_ids).not_to be_empty
  end
end
