require "spec_helper"

RSpec.describe Textus::Action::Put do
  describe "write cascade" do
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

    it "put to canon triggers materialize for the dependent entry (cascade job)" do
      store = with_derived_store(root)
      expect do
        store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "hello world")
      end.not_to raise_error
    end
  end
end
