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
                              })
  end

  let(:call) { test_ctx(role: "automation") }

  before do
    store
    path = File.join(root, "zones/feeds/stale.md")
    old = Time.now - (2 * 24 * 3600)
    File.utime(old, old, path) if File.exist?(path)
  end

  it "produces all derived entries (Phase 1)" do
    expect(result["produced"]).to include("feeds.catalog")
    expect(File.read(File.join(root, "zones/feeds/catalog.json"))).to include("Apple")
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

  describe "prefix scoping" do
    it "produces and sweeps nothing under a non-matching prefix, leaving the tree intact" do
      scoped = described_class.new(container: store.container, call: call).call(prefix: "nonexistent")
      expect(scoped["produced"]).to be_empty
      expect(scoped["archived"]).to be_empty
      expect(scoped["dropped"]).to be_empty
      # the aged leaf that an unscoped pass WOULD archive is untouched
      expect(File.exist?(File.join(root, "zones/feeds/stale.md"))).to be(true)
      expect(File.exist?(File.join(root, "zones/feeds/catalog.json"))).to be(false)
    end

    it "scopes produce to entries under the matching prefix" do
      scoped = described_class.new(container: store.container, call: call).call(prefix: "feeds.catalog")
      expect(scoped["produced"]).to contain_exactly("feeds.catalog")
      # feeds.stale is outside the prefix, so it is not archived this pass
      expect(scoped["archived"]).to be_empty
      expect(File.exist?(File.join(root, "zones/feeds/stale.md"))).to be(true)
    end
  end

  describe "sweep failure isolation (:reconcile_failed)" do
    # A canon entry under a retention rule: the automation caller lacks `author`,
    # so KeyDelete raises WriteForbidden — a real Textus::Error landing in the
    # swept[:failed] bucket. reconcile must publish :reconcile_failed and return
    # the key in `failed` without raising.
    let(:store) do
      store_from_manifest(root, zones: %w[knowledge feeds],
                                manifest: <<~YAML,
                                  version: textus/3
                                  zones:
                                    - { name: knowledge, kind: canon }
                                    - { name: feeds, kind: machine }
                                  entries:
                                    - { key: knowledge.locked, path: knowledge/locked.md, zone: knowledge, kind: leaf }
                                  rules:
                                    - { match: "knowledge.locked", retention: { ttl: 1d, action: drop } }
                                YAML
                                files: { "zones/knowledge/locked.md" => "---\n---\nx\n" })
    end

    before do
      store
      path = File.join(root, "zones/knowledge/locked.md")
      old = Time.now - (2 * 24 * 3600)
      File.utime(old, old, path)
    end

    it "returns the failed key and publishes :reconcile_failed without raising" do
      fired = []
      store.container.events.on(:reconcile_failed, :probe) { |failed:, **| fired << failed }

      out = nil
      expect do
        out = described_class.new(container: store.container, call: call).call
      end.not_to raise_error

      expect(out["failed"].map { |f| f["key"] }).to include("knowledge.locked")
      expect(out["ok"]).to be(false)
      expect(fired).not_to be_empty
      expect(fired.first.map { |f| f["key"] }).to include("knowledge.locked")
      # the protected entry survived the failed sweep
      expect(File.exist?(File.join(root, "zones/knowledge/locked.md"))).to be(true)
    end
  end
end
