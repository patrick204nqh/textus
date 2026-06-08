require "spec_helper"

# Phase 2 proves `drain` converges equivalently to `reconcile` (the filesystem
# effect — derived entries produced, aged leaves archived) before Phase 4 renames
# reconcile away. We assert the EFFECT, not the result hash: the two verbs return
# intentionally different shapes (reconcile: produced/dropped/archived; drain:
# completed/failed). reconcile itself is left untouched here — it is deleted in
# Phase 4 — so its own specs keep passing.
RSpec.describe Textus::Maintenance::Drain do # convergence parity with reconcile
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root, zones: %w[knowledge feeds],
            manifest: <<~YAML,
              version: textus/3
              zones:
                - { name: knowledge, kind: canon }
                - { name: feeds, kind: machine }
              entries:
                - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }
                - { key: feeds.stale, path: feeds/stale.md, zone: feeds, kind: leaf }
                - key: feeds.catalog
                  kind: produced
                  path: feeds/catalog.json
                  zone: feeds
                  source: { from: project, select: "knowledge", pluck: [title] }
                  publish:
                    - { to: CATALOG.md, template: catalog.mustache }
              rules:
                - { match: "feeds.stale", retention: { ttl: 1d, action: archive } }
            YAML
            files: {
              "zones/knowledge/a.md" => "---\ntitle: Apple\n---\nx\n",
              "zones/feeds/stale.md" => "---\n---\nold\n",
              "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
            }
    )
  end

  before do
    store
    path = File.join(root, "zones/feeds/stale.md")
    old = Time.now - (2 * 24 * 3600)
    File.utime(old, old, path) if File.exist?(path)
  end

  it "drain produces derived entries and archives aged leaves, like reconcile" do
    store.as("automation").drain
    expect(File.read(File.join(root, "zones/feeds/catalog.json"))).to include("Apple")
    expect(File.exist?(File.join(root, "archive/zones/feeds/stale.md"))).to be(true)
    expect(File.exist?(File.join(root, "zones/feeds/stale.md"))).to be(false)
  end

  it "is a content no-op on a converged store (re-drain leaves an empty queue, ok)" do
    store.as("automation").drain
    result = store.as("automation").drain
    expect(result["ok"]).to be true
    expect(Textus::Ports::Queue.new(root: root).ready_ids).to be_empty
  end
end
