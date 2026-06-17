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
          - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
          - key: feeds.catalog
            kind: produced
            path: feeds/catalog.json
            lane: feeds
            source: { from: external, command: "make", sources: [] }
      YAML

      store_from_manifest(
        root,
        lanes: %w[knowledge feeds],
        manifest: manifest,
        files: { "templates/catalog.erb" => "<% Array(entries).each do |e| %><%= e[\"title\"] %>\n<% end -%>" },
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
