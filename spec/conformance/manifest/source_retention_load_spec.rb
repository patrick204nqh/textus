require "spec_helper"

RSpec.describe "source/retention manifest load (ADR 0093)" do
  include_context "textus_store_fixture"

  def load(manifest)
    store_from_manifest(root, zones: %w[feeds knowledge], manifest: manifest).manifest
  end

  it "rejects a legacy upkeep: rule with a fold hint" do
    expect { load(<<~YAML) }.to raise_error(Textus::BadManifest, /upkeep.*removed|retention:|source:/i)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries: [{ key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }]
      rules:
        - { match: "knowledge.*", upkeep: { ttl: 1d, action: drop } }
    YAML
  end

  it "rejects retention: drop on a derived entry" do
    expect { load(<<~YAML) }.to raise_error(Textus::BadManifest, /derived/)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - key: feeds.cat
          kind: produced
          path: feeds/cat.json
          zone: feeds
          source: { from: project, select: "knowledge.*" }
      rules:
        - { match: "feeds.cat", retention: { ttl: 1d, action: drop } }
    YAML
  end

  it "accepts an intake source with an orthogonal retention rule" do
    m = load(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - key: feeds.doc
          kind: produced
          path: feeds/doc.md
          zone: feeds
          source: { from: handler, handler: h, ttl: 1h }
      rules:
        - { match: "feeds.doc", retention: { ttl: 90d, action: archive } }
    YAML
    expect(m.rules.for("feeds.doc").retention.action).to eq(:archive)
  end

  it "rejects an unknown key inside source:" do
    expect { load(<<~YAML) }.to raise_error(Textus::BadManifest, /unknown key 'bogus'/)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - { key: feeds.cat, kind: produced, path: feeds/cat.md, zone: feeds, source: { from: template, template: c, bogus: 1 } }
    YAML
  end
end
