require "spec_helper"

RSpec.describe Textus::Jobs::Planner do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root, lanes: %w[knowledge feeds],
            manifest: <<~YAML,
              version: textus/4
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
                    - { to: CATALOG.md, template: catalog.erb }
                - key: feeds.doc
                  kind: produced
                  path: feeds/doc.md
                  lane: feeds
                  source: { from: external, command: "make", sources: [] }
            YAML
            files: {
              "data/knowledge/a.md" => "---\ntitle: Apple\n---\nx\n",
              "templates/catalog.erb" => "<% Array(entries).each do |e| %><%= e[\"title\"] %>\n<% end -%>",
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
    store_port = Textus::Ports::Store.new(root: store.root).setup!
    queue = Textus::Jobs::Queue.new(store: store_port)
    described_class.seed(container: store.container, queue: queue, role: "automation")
    expect(queue.ready_ids).not_to be_empty
    ids = queue.ready_ids
    expect(ids).to include(a_string_starting_with("index:"))
    expect(ids.count { |id| id.start_with?("index:") }).to eq(1)
    store_port.close
  end
end
