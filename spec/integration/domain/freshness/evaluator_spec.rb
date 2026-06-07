require "spec_helper"

RSpec.describe Textus::Domain::Freshness::Evaluator do
  subject(:evaluator) do
    described_class.new(
      manifest: store.manifest,
      file_stat: Textus::Ports::Storage::FileStat.new,
      clock: Textus::Ports::Clock,
    )
  end

  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[feeds], manifest: <<~YAML,
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - { key: feeds.doc, kind: produced, path: feeds/doc.md, zone: feeds, source: { from: handler, handler: h, ttl: 1h } }
        - { key: feeds.nocadence, kind: produced, path: feeds/nocadence.md, zone: feeds, source: { from: handler, handler: h } }
    YAML
                              files: {
                                "zones/feeds/doc.md" => "---\n---\nbody\n",
                                "zones/feeds/nocadence.md" => "---\n---\nbody\n",
                              })
  end

  before { store }

  def mentry(key = "feeds.doc") = store.manifest.data.entries.find { |e| e.key == key }

  describe "#verdict (per-entry currency)" do
    it "is fresh for a recently-written intake entry" do
      expect(evaluator.verdict(mentry).stale).to be(false)
    end

    it "is stale for an intake entry past its source.ttl" do
      path = File.join(root, "zones/feeds/doc.md")
      old  = Time.now - (2 * 3600)
      File.utime(old, old, path)
      v = evaluator.verdict(mentry)
      expect(v.stale).to be(true)
      expect(v.reason).to eq("ttl exceeded")
    end

    it "is fresh for a ttl-less intake entry (no declared cadence)" do
      path = File.join(root, "zones/feeds/nocadence.md")
      old  = Time.now - (100 * 3600)
      File.utime(old, old, path)
      expect(evaluator.verdict(mentry("feeds.nocadence")).stale).to be(false)
    end
  end

  describe "#stale_intake_keys (reconcile scope)" do
    it "lists an intake entry past its source.ttl" do
      path = File.join(root, "zones/feeds/doc.md")
      old  = Time.now - (2 * 3600)
      File.utime(old, old, path)
      expect(evaluator.stale_intake_keys).to eq(["feeds.doc"])
    end

    it "omits a fresh intake entry" do
      expect(evaluator.stale_intake_keys).to be_empty
    end

    it "skips a ttl-less intake entry even when old (:no_policy)" do
      path = File.join(root, "zones/feeds/nocadence.md")
      old  = Time.now - (100 * 3600)
      File.utime(old, old, path)
      expect(evaluator.stale_intake_keys).not_to include("feeds.nocadence")
    end

    it "treats a never-recorded intake entry (file missing, ttl set) as stale" do
      File.delete(File.join(root, "zones/feeds/doc.md"))
      expect(evaluator.stale_intake_keys).to include("feeds.doc")
    end
  end
end
