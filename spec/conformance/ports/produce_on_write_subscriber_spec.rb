require "spec_helper"

RSpec.describe "produce-on-write (ADR 0093, async-only)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge feeds],
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
                              YAML
                              files: { "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}" })
  end
  let(:queue) { Textus::Ports::Queue.new(root: root) }

  it "a canon write enqueues a materialize job for the dependent, fresh after drain" do
    store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "x\n")
    expect(queue.ready_ids).not_to be_empty
    expect(queue.ready_ids).to all(start_with("materialize:"))

    store.as("automation").drain
    expect(File.read(File.join(root, "data/feeds/catalog.json"))).to include("Apple")
  end

  it "stamps automation authority on the enqueued job (produce self-elevates)" do
    store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "x\n")
    id = queue.ready_ids.first
    body = JSON.parse(File.read(File.join(Textus::Layout.queue_state(root, :ready), "#{id}.json")))
    expect(body["enqueued_by"]).to eq("automation")
  end

  it "a source deletion enqueues materialize for its dependents (ADR 0087 gap closed)" do
    store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "x\n")
    queue.purge(:ready) # drop the put's enqueued job; isolate the delete

    store.as("human").key_delete("knowledge.a")

    expect(queue.ready_ids).not_to be_empty
    expect(queue.ready_ids).to all(start_with("materialize:"))
  end

  it "recursion guard: a write INTO a derived entry does not fan out" do
    store # boot (attaches the subscriber)
    subscriber = Textus::Ports::ProduceOnWriteSubscriber.new(store.container)

    # produce OUTPUT is a write to a derived key; it must NOT re-trigger Produce,
    # or every rebuild would loop. The guard short-circuits BEFORE the rdeps
    # lookup, so asserting Rdeps is never consulted proves the guard fired.
    allow(Textus::Read::Rdeps).to receive(:new).and_call_original

    subscriber.on_write(key: "feeds.catalog")

    expect(Textus::Read::Rdeps).not_to have_received(:new)
    expect(queue.ready_ids).to be_empty
  end
end
