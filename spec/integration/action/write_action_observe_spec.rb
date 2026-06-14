require "spec_helper"

RSpec.describe Textus::Action::Put do
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

  it "materializes dependent entries inline from write cascade" do
    store = with_derived_store(root)
    store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "hello world")

    catalog_path = File.join(root, "data/feeds/catalog.json")
    expect(File.read(catalog_path)).to include("Apple")
  end
end
