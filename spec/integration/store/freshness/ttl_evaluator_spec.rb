require "spec_helper"

RSpec.describe Textus::Store::Freshness::TtlEvaluator do
  include_context "textus_store_fixture"

  let(:no_ttl_store) do
    store_from_manifest(
      File.join(tmp, ".textus_no_ttl"),
      lanes: %w[knowledge],
      manifest: <<~YAML,
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, lane: knowledge, kind: leaf }
      YAML
    )
  end

  let(:ttl_store) do
    store_from_manifest(root, lanes: %w[feeds], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: automation, can: [converge] }
      lanes:
        - { name: feeds, kind: machine }
      entries:
        - key: feeds.item
          path: feeds/item.json
          lane: feeds
          kind: leaf
      rules:
        - match: "feeds.**"
          retention: { ttl: 1s, action: drop }
    YAML
  end

  let(:file_stat) { Textus::Port::Storage::FileStat.new }
  let(:clock)     { Textus::Port::Clock.new }

  describe "#verdict" do
    it "returns a fresh verdict when no retention rule applies" do
      ev = described_class.new(
        manifest: no_ttl_store.container.manifest,
        file_stat: file_stat,
        clock: clock,
      )
      mentry = no_ttl_store.container.manifest.data.entries.first
      expect(ev.verdict(mentry).stale).to be false
    end

    it "returns a stale verdict when file mtime exceeds ttl" do
      ev = described_class.new(
        manifest: ttl_store.container.manifest,
        file_stat: file_stat,
        clock: clock,
      )
      mentry = ttl_store.container.manifest.data.entries.first
      allow(file_stat).to receive_messages(exists?: true, mtime: Time.now - 10)
      verdict = ev.verdict(mentry)
      expect(verdict.stale).to be true
      expect(verdict.reason).to eq("ttl exceeded")
    end
  end

  describe "#stale_keys" do
    it "returns empty when no retention rule is declared" do
      ev = described_class.new(
        manifest: no_ttl_store.container.manifest,
        file_stat: file_stat,
        clock: clock,
      )
      expect(ev.stale_keys).to eq([])
    end
  end
end
