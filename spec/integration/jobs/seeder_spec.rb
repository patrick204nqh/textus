require "spec_helper"

RSpec.describe Textus::Jobs::Seeder do
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
            YAML
            files: {
              "data/knowledge/a.md" => "---\ntitle: Apple\n---\nx\n",
              "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
            }
    )
  end
  let(:queue) { Textus::Ports::Queue.new(root: root) }

  def seed(role: "human")
    described_class.new(container: store.container, queue: queue, call: test_ctx(role: role)).seed(prefix: nil, zone: nil)
  end

  it "enqueues a materialize job per producible key plus a sweep job" do
    seed
    ids = queue.ready_ids
    expect(ids).to include(a_string_starting_with("sweep:"))
    expect(ids).to include(a_string_starting_with("materialize:"))
  end

  it "stamps the caller's role on the sweep job (destructive runs as caller)" do
    seed(role: "human")
    sweep_id = queue.ready_ids.find { |i| i.start_with?("sweep:") }
    body = JSON.parse(File.read(File.join(Textus::Layout.queue_state(root, :ready), "#{sweep_id}.json")))
    expect(body["enqueued_by"]).to eq("human")
  end
end
