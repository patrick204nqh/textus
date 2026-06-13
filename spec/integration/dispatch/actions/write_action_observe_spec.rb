require "spec_helper"

RSpec.describe Textus::Dispatch::Actions::WriteAction do
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

  it "enqueues an observe action from entry.written cascade" do
    store = with_derived_store(root)
    store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "hello world")

    queue = Textus::Ports::Queue.new(root: root)
    expect(queue.ready_ids.grep(/observe:/)).not_to be_empty
  end
end
