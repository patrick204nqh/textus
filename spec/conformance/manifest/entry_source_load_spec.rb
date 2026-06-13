require "spec_helper"

RSpec.describe "entries load from source: (ADR 0093)" do
  include_context "textus_store_fixture"

  it "loads intake + derived entries declared via source:" do
    store = store_from_manifest(root, lanes: %w[feeds knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: feeds, kind: machine }
        - { name: knowledge, kind: canon }
      entries:
        - { key: feeds.doc, kind: produced, path: data/feeds/doc.md, lane: feeds, source: { from: fetch, handler: h, ttl: 1h } }
        - key: feeds.cat
          kind: produced
          path: data/feeds/cat.json
          lane: feeds
          source: { from: derive, select: "knowledge.*", pluck: [key] }
    YAML
    doc = store.manifest.resolver.resolve("feeds.doc").entry
    cat = store.manifest.resolver.resolve("feeds.cat").entry
    expect(doc.intake?).to be(true)
    expect(doc.handler).to eq("h")
    expect(cat.derived?).to be(true)
    expect(cat.projection?).to be(true)
    expect(cat.source.select).to eq("knowledge.*")
  end

  it "derives the produce method from source.from (ADR 0095: no kind/source mismatch)" do
    store = store_from_manifest(root, lanes: %w[feeds], manifest: <<~YAML)
      version: textus/3
      lanes: [{ name: feeds, kind: machine }]
      entries:
        - { key: feeds.x, kind: produced, path: data/feeds/x.md, lane: feeds, source: { from: derive, select: "knowledge.*" } }
    YAML
    x = store.manifest.resolver.resolve("feeds.x").entry
    expect(x.derived?).to be(true)
    expect(x.intake?).to be(false)
  end
end
