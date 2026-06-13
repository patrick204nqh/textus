require "spec_helper"

RSpec.describe Textus::Dispatch::Actions::WriteAction do
  describe "write cascade through gate" do
    include_context "textus_store_fixture"

    def with_derived_store(root)
      manifest = <<~YAML
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
      YAML

      store_from_manifest(
        root,
        lanes: %w[knowledge feeds],
        manifest: manifest,
        files: { "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}" },
      )
    end

    it "put to canon enqueues materialize job for a dependent entry" do
      store = with_derived_store(root)
      store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "hello world")

      queue = Textus::Ports::Queue.new(root: root)
      ready = queue.ready_ids
      expect(ready).not_to be_empty

      job_file = Dir[File.join(root, ".run", "queue", "ready", "*.json")].first
      job_data = JSON.parse(File.read(job_file))
      expect(job_data.fetch("type")).to include("materialize")
    end
  end
end
