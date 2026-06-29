require "spec_helper"

RSpec.describe Textus::Store::Freshness::DriftDetector do
  subject(:detector) do
    described_class.new(
      manifest: store.container.manifest,
      file_stat: file_stat,
      clock: clock,
    )
  end

  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge feeds], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: automation, can: [converge] }
        - { name: human, can: [author] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: feeds, kind: machine }
      entries:
        - { key: knowledge.src, path: knowledge/src.md, lane: knowledge, kind: leaf }
        - key: feeds.derived
          kind: produced
          path: feeds/derived.json
          lane: feeds
          source: { from: external, command: "gen", sources: [knowledge.src] }
    YAML
  end

  let(:file_stat) { Textus::Port::Storage::FileStat.new }
  let(:clock)     { Textus::Port::Clock.new }

  describe "#drift_rows" do
    it "returns empty for a non-external entry" do
      leaf = store.container.manifest.data.entries.find { |e| e.key == "knowledge.src" }
      expect(detector.drift_rows(leaf)).to eq([])
    end

    it "returns a drift row when the derived file has never been generated" do
      derived = store.container.manifest.data.entries.find { |e| e.key == "feeds.derived" }
      allow(file_stat).to receive(:exists?).and_return(false)
      rows = detector.drift_rows(derived)
      expect(rows.size).to eq(1)
      expect(rows.first["reason"]).to eq("derived entry has never been generated")
      expect(rows.first["key"]).to eq("feeds.derived")
    end
  end
end
