RSpec.describe "Textus::Core::Retention::Sweep -- GC reporting" do
  include_context "textus_store_fixture"
  include_context "core domain doubles"

  let(:store) do
    store_from_manifest(root, lanes: %w[feeds], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: feeds, kind: machine }
      entries:
        - key: feeds.event
          kind: produced
          path: data/feeds/event.md
          lane: feeds
          source: { from: fetch, handler: http_json, ttl: 1h }
      rules:
        - { match: feeds.event, retention: { ttl: 7d, action: drop } }
    YAML
  end

  let(:sweep) do
    Textus::Core::Retention::Sweep.new(
      manifest: store.manifest, file_stat: fake_file_stat, clock: fake_clock,
    )
  end

  let(:entry_path) { store.manifest.resolver.resolve("feeds.event").path }

  # Writes the file on disk (so Resolver#enumerate can find it via File.exist?)
  # AND registers it in the fake_file_stat for mtime/exists? checks.
  def create_entry(mtime_age:)
    FileUtils.mkdir_p(File.dirname(entry_path))
    File.write(entry_path, "content")
    register_file(entry_path, mtime: frozen_now - mtime_age)
  end

  describe "#call" do
    it "returns empty when the file does not exist" do
      expect(sweep.call).to be_empty
    end

    it "returns empty when the file is within the retention ttl" do
      create_entry(mtime_age: 3 * 86_400)
      expect(sweep.call).to be_empty
    end

    it "returns a row when the file is past the retention ttl" do
      create_entry(mtime_age: 8 * 86_400)
      rows = sweep.call
      expect(rows.length).to eq(1)
      expect(rows.first).to include("key" => "feeds.event", "action" => "drop")
    end

    it "reports the correct file path in the row" do
      create_entry(mtime_age: 8 * 86_400)
      expect(sweep.call.first["path"]).to eq(entry_path)
    end
  end

  describe "#call with lane filter" do
    it "returns empty when the lane filter does not match the entry" do
      create_entry(mtime_age: 8 * 86_400)
      expect(sweep.call(lane: "knowledge")).to be_empty
    end

    it "returns the row when the lane filter matches" do
      create_entry(mtime_age: 8 * 86_400)
      expect(sweep.call(lane: "feeds")).not_to be_empty
    end
  end
end
