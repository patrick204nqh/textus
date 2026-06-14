RSpec.describe "Textus::Core::Freshness::Evaluator — currency verdicts" do
  include_context "textus_store_fixture"
  include_context "core domain doubles"

  let(:store) do
    store_from_manifest(root, lanes: %w[feeds knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: feeds,     kind: machine }
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, kind: leaf,     path: data/knowledge/doc.md, lane: knowledge }
        - key: feeds.weather
          kind: produced
          path: data/feeds/weather.md
          lane: feeds
          source: { from: fetch, handler: http_json, ttl: 1h }
    YAML
  end

  let(:evaluator) do
    Textus::Core::Freshness::Evaluator.new(
      manifest: store.manifest, file_stat: fake_file_stat, clock: fake_clock,
    )
  end

  let(:leaf_entry)   { store.manifest.data.entries.find { |e| e.key == "knowledge.doc" } }
  let(:intake_entry) { store.manifest.data.entries.find { |e| e.key == "feeds.weather" } }
  let(:intake_path)  { store.manifest.resolver.resolve("feeds.weather").path }

  describe "#verdict" do
    it "returns fresh for a non-intake (leaf) entry" do
      verdict = evaluator.verdict(leaf_entry)
      expect(verdict.stale).to be false
    end

    it "returns fresh (no_policy) for an intake entry with no ttl" do
      store2 = store_from_manifest(root.sub(".textus", ".textus2"), lanes: %w[feeds], manifest: <<~YAML)
        version: textus/3
        lanes:
          - { name: feeds, kind: machine }
        entries:
          - { key: feeds.raw, kind: produced, path: data/feeds/raw.md, lane: feeds,
              source: { from: fetch, handler: noop } }
      YAML
      no_ttl_entry = store2.manifest.data.entries.first
      ev2 = Textus::Core::Freshness::Evaluator.new(
        manifest: store2.manifest, file_stat: fake_file_stat, clock: fake_clock,
      )
      expect(ev2.verdict(no_ttl_entry).stale).to be false
    end

    it "returns stale when the file mtime is older than ttl" do
      register_file(intake_path, mtime: frozen_now - 7200)
      expect(evaluator.verdict(intake_entry).stale).to be true
    end

    it "returns fresh when the file mtime is within ttl" do
      register_file(intake_path, mtime: frozen_now - 1800)
      expect(evaluator.verdict(intake_entry).stale).to be false
    end

    it "returns stale when the file does not exist yet" do
      expect(evaluator.verdict(intake_entry).stale).to be true
    end
  end

  describe "#stale_intake_keys" do
    it "returns empty when no intake entries are stale" do
      register_file(intake_path, mtime: frozen_now - 1800)
      expect(evaluator.stale_intake_keys).to be_empty
    end

    it "includes the key of a stale intake entry" do
      register_file(intake_path, mtime: frozen_now - 7200)
      expect(evaluator.stale_intake_keys).to include("feeds.weather")
    end

    it "excludes non-intake entries regardless of mtime" do
      register_file(intake_path, mtime: frozen_now - 7200)
      expect(evaluator.stale_intake_keys).not_to include("knowledge.doc")
    end
  end
end
