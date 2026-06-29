require "spec_helper"

RSpec.describe "cascade reactive materialise" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge feeds], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: automation, can: [converge] }
        - { name: human, can: [author] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: feeds, kind: machine }
      entries:
        - { key: knowledge.source, path: knowledge/source.md, lane: knowledge, kind: leaf }
        - key: feeds.derived
          kind: produced
          path: feeds/derived.json
          lane: feeds
          source: { from: external, command: "true", sources: [knowledge.source] }
          publish:
            - { to: DERIVED.md, template: t.erb }
    YAML
  end

  it "enqueues a materialise job for a dependent entry when its source is written" do
    queue = Textus::Store::Jobs::Queue.new(store: store.container.job_store)
    queue.purge(:ready)

    store.with_role("human").put("knowledge.source", body: "hello")

    ready = queue.ready_ids
    expect(ready).to include(a_string_starting_with("materialize:"))
  end

  it "does not enqueue materialize jobs when no entries depend on the written key" do
    other_root = File.join(tmp, ".textus2")
    store2 = store_from_manifest(other_root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: human, can: [author] }
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
        - { key: knowledge.b, path: knowledge/b.md, lane: knowledge, kind: leaf }
    YAML
    queue = Textus::Store::Jobs::Queue.new(store: store2.container.job_store)
    queue.purge(:ready)

    store2.with_role("human").put("knowledge.a", body: "x")

    expect(queue.ready_ids).to be_empty
  end
end
