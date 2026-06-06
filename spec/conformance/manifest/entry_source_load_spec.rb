require "spec_helper"

RSpec.describe "entries load from source: (ADR 0093)" do
  include_context "textus_store_fixture"

  it "loads intake + derived entries declared via source:" do
    store = store_from_manifest(root, zones: %w[feeds knowledge], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: machine }
        - { name: knowledge, kind: canon }
      entries:
        - { key: feeds.doc, kind: intake, path: feeds/doc.md, zone: feeds, source: { from: handler, handler: h, ttl: 1h } }
        - key: feeds.cat
          kind: derived
          path: feeds/cat.md
          zone: feeds
          source: { from: template, template: c.mustache, project: { select: "knowledge.*", pluck: [key] } }
    YAML
    doc = store.manifest.resolver.resolve("feeds.doc").entry
    cat = store.manifest.resolver.resolve("feeds.cat").entry
    expect(doc.intake?).to be(true)
    expect(doc.handler).to eq("h")
    expect(cat.derived?).to be(true)
    expect(cat.projection?).to be(true)
    expect(cat.template).to eq("c.mustache")
  end

  it "rejects a kind/source mismatch (kind: intake with from: template)" do
    expect do
      store_from_manifest(root, zones: %w[feeds], manifest: <<~YAML)
        version: textus/3
        zones: [{ name: feeds, kind: machine }]
        entries:
          - { key: feeds.x, kind: intake, path: feeds/x.md, zone: feeds, source: { from: template, template: c } }
      YAML
    end.to raise_error(Textus::Error, /intake needs source.from: handler/)
  end
end
