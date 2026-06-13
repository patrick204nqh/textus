require "spec_helper"

RSpec.describe "produced kind load (ADR 0095)" do
  include_context "textus_store_fixture"

  def load(manifest) = store_from_manifest(root, lanes: %w[feeds], manifest: manifest).manifest

  it "accepts kind: produced with a source" do
    m = load(<<~YAML)
      version: textus/3
      lanes: [{ name: feeds, kind: machine }]
      entries:
        - { key: feeds.doc, kind: produced, path: data/feeds/doc.json, lane: feeds, source: { from: fetch, handler: h } }
    YAML
    e = m.data.entries.find { |x| x.key == "feeds.doc" }
    expect(e.intake?).to be(true)
  end

  it "rejects retired kind: derived with a fold hint" do
    expect { load(<<~YAML) }.to raise_error(Textus::BadManifest, /produced.*ADR 0095|kind: produced/)
      version: textus/3
      lanes: [{ name: feeds, kind: machine }]
      entries:
        - { key: feeds.x, kind: derived, path: data/feeds/x.json, lane: feeds, source: { from: derive, select: [feeds.doc] } }
    YAML
  end
end
