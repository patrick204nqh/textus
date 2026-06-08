require "spec_helper"

RSpec.describe Textus::Domain::Freshness::Evaluator do
  subject(:evaluator) do
    described_class.new(
      manifest: store.manifest,
      file_stat: Textus::Ports::Storage::FileStat.new,
      clock: Textus::Ports::Clock.new,
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

  describe "#drift_rows (filesystem directory-source)" do
    # Reproduces the directory-source scenario deleted from the conformance tier
    # (staleness_signal_spec.rb).  Exercises check_filesystem_source ->
    # dir_has_newer_file? / file?  — in particular the branch where a regular
    # file inside the source dir is newer than generated.at while subdirectories
    # are skipped (not treated as "newer files").
    subject(:dir_evaluator) do
      described_class.new(
        manifest: dir_store.manifest,
        file_stat: Textus::Ports::Storage::FileStat.new,
        clock: Textus::Ports::Clock.new,
      )
    end

    let(:src_dir) { File.join(tmp, "src") }

    let(:dir_store) do
      FileUtils.mkdir_p(File.join(src_dir, "subdir"))
      File.write(File.join(src_dir, "data.txt"), "content")
      future = Time.now + 3600
      [File.join(src_dir, "subdir"), File.join(src_dir, "data.txt")].each do |f|
        File.utime(future, future, f)
      end

      store_from_manifest(root, zones: %w[artifacts], manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: artifacts, kind: machine }
        entries:
          - key: artifacts.report
            kind: produced
            path: artifacts/report.md
            zone: artifacts
            source:
              from: command
              command: "make report"
              sources: ["#{src_dir}"]
      YAML
                                files: {
                                  "zones/artifacts/report.md" => <<~MD,
                                    ---
                                    generated:
                                      by: "make report"
                                      at: "2020-01-01T00:00:00Z"
                                      from: []
                                    ---
                                    report
                                  MD
                                })
    end

    def dir_mentry = dir_store.manifest.data.entries.find { |e| e.key == "artifacts.report" }

    it "flags drift when a regular file in the source directory is newer than generated.at" do
      rows = dir_evaluator.drift_rows(dir_mentry)
      expect(rows.length).to eq(1)
      expect(rows.first["key"]).to eq("artifacts.report")
      expect(rows.first["reason"]).to match(/modified after generated\.at/)
    end

    it "skips subdirectories under the source dir (does not mistake a subdir mtime as drift)" do
      # Trigger dir_store setup (creates data.txt), then remove the regular file
      # so only the subdir remains.  The subdir mtime is also in the future but
      # dir_has_newer_file? must skip directories — expect no drift row.
      dir_store # ensure fixture is written before we delete into it
      File.delete(File.join(src_dir, "data.txt"))
      rows = dir_evaluator.drift_rows(dir_mentry)
      expect(rows).to be_empty
    end
  end
end
