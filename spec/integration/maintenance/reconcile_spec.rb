require "spec_helper"

RSpec.describe Textus::Maintenance::Reconcile do
  subject(:result) { described_class.new(container: store.container, call: call).call }

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
                                  - { key: feeds.stale, path: feeds/stale.md, zone: feeds, kind: leaf }
                                  - key: feeds.catalog
                                    kind: derived
                                    path: feeds/catalog.md
                                    zone: feeds
                                    source: { from: template, template: catalog.mustache, project: { select: "knowledge", pluck: [title] } }
                                rules:
                                  - { match: "feeds.stale", retention: { ttl: 1d, action: archive } }
                              YAML
                              files: {
                                "zones/knowledge/a.md" => "---\ntitle: Apple\n---\nx\n",
                                "zones/feeds/stale.md" => "---\n---\nold\n",
                                "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
                              })
  end

  let(:call) { test_ctx(role: "automation") }

  before do
    store
    path = File.join(root, "zones/feeds/stale.md")
    old = Time.now - (2 * 24 * 3600)
    File.utime(old, old, path)
  end

  it "produces all derived entries (Phase 1)" do
    expect(result["produced"]).to include("feeds.catalog")
    expect(File.read(File.join(root, "zones/feeds/catalog.md"))).to include("Apple")
  end

  it "archives an aged machine leaf (Phase 2, as the caller)" do
    expect(result["archived"]).to include("feeds.stale")
    expect(File.exist?(File.join(root, "archive/zones/feeds/stale.md"))).to be(true)
    expect(File.exist?(File.join(root, "zones/feeds/stale.md"))).to be(false)
  end

  it "dry-run reports would_* without mutating" do
    dry = described_class.new(container: store.container, call: call).call(dry_run: true)
    expect(dry["would_produce"]).to include("feeds.catalog")
    expect(dry["would_archive"]).to include("feeds.stale")
    expect(File.exist?(File.join(root, "zones/feeds/stale.md"))).to be(true)
  end
end
