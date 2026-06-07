require "spec_helper"

RSpec.describe "produce-on-write (ADR 0093)" do
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
                                    kind: derived
                                    path: feeds/catalog.json
                                    zone: feeds
                                    source:
                                      from: project
                                      on_write: sync
                                      select: "knowledge"
                                      pluck: [title]
                              YAML
                              files: { "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}" })
  end

  it "sync source: a canon write leaves the dependent derived fresh on return" do
    store.as("human").put("knowledge.a", meta: { "title" => "Apple" }, body: "x\n")
    expect(File.read(File.join(root, "zones/feeds/catalog.json"))).to include("Apple")
  end

  it "recursion guard: a write INTO a derived entry does not fan out" do
    store # boot (attaches the subscriber)
    subscriber = Textus::Ports::ProduceOnWriteSubscriber.new(store.container)
    call = Textus::Call.build(role: "automation")

    # produce OUTPUT is a write to a derived key; it must NOT re-trigger Produce,
    # or every rebuild would loop. The guard short-circuits BEFORE the rdeps
    # lookup, so asserting Rdeps is never consulted proves the guard fired
    # (not merely an empty blast radius).
    allow(Textus::Read::Rdeps).to receive(:new).and_call_original
    allow(Textus::Maintenance::Produce).to receive(:converge)
    allow(Textus::Maintenance::Produce::AsyncRunner).to receive(:enqueue)

    subscriber.on_write(key: "feeds.catalog", call: call)

    expect(Textus::Read::Rdeps).not_to have_received(:new)
    expect(Textus::Maintenance::Produce).not_to have_received(:converge)
    expect(Textus::Maintenance::Produce::AsyncRunner).not_to have_received(:enqueue)
  end

  describe "async source (default on_write)" do
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
                                      kind: derived
                                      path: feeds/catalog.json
                                      zone: feeds
                                      source:
                                        from: project
                                        select: "knowledge"
                                        pluck: [title]
                                YAML
                                files: { "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}" })
    end

    it "async source: enqueues a deferred rebuild that lands fresh after drain" do
      store.as("human").put("knowledge.a", meta: { "title" => "Banana" }, body: "x\n")
      Textus::Maintenance::Produce::AsyncRunner.drain
      expect(File.read(File.join(root, "zones/feeds/catalog.json"))).to include("Banana")
    end
  end
end
