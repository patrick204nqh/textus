require "spec_helper"
require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe Textus::Migrate::Zones do
  let(:tmp) { Dir.mktmpdir }
  let(:root) { tmp }
  let(:manifest_path) { File.join(root, ".textus/manifest.yaml") }

  before do
    FileUtils.mkdir_p(File.join(root, ".textus/zones/canon"))
    FileUtils.mkdir_p(File.join(root, ".textus/zones/working"))
    FileUtils.mkdir_p(File.join(root, ".textus/zones/intake"))
    FileUtils.mkdir_p(File.join(root, ".textus/zones/pending"))
    FileUtils.mkdir_p(File.join(root, ".textus/zones/derived"))
    File.write(manifest_path, <<~YAML)
      version: textus/2
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: working, writable_by: [human, ai, script] }
        - { name: intake,  writable_by: [script] }
        - { name: pending, writable_by: [ai, human] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: canon.identity, path: canon/identity.md, zone: canon }
        - { key: working.notes,  path: working/notes,     zone: working, nested: true }
        - { key: intake.news.hn, path: intake/news/hn.md, zone: intake }
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  describe "#call" do
    it "renames default zone entries in manifest" do
      described_class.new(root: root).call
      yaml = YAML.load_file(manifest_path)
      zone_names = yaml["zones"].map { |z| z["name"] }
      expect(zone_names).to contain_exactly("identity", "working", "inbox", "review", "output")
    end

    it "moves the on-disk zone directories" do
      described_class.new(root: root).call
      expect(Dir.exist?(File.join(root, ".textus/zones/identity"))).to be(true)
      expect(Dir.exist?(File.join(root, ".textus/zones/inbox"))).to be(true)
      expect(Dir.exist?(File.join(root, ".textus/zones/review"))).to be(true)
      expect(Dir.exist?(File.join(root, ".textus/zones/output"))).to be(true)
      expect(Dir.exist?(File.join(root, ".textus/zones/canon"))).to be(false)
      expect(Dir.exist?(File.join(root, ".textus/zones/intake"))).to be(false)
    end

    it "rewrites every entry's zone: and path: fields" do
      described_class.new(root: root).call
      yaml = YAML.load_file(manifest_path)
      news = yaml["entries"].find { |e| e["key"] == "intake.news.hn" }
      expect(news["zone"]).to eq("inbox")
      expect(news["path"]).to eq("inbox/news/hn.md")
      ident = yaml["entries"].find { |e| e["key"] == "canon.identity" }
      expect(ident["zone"]).to eq("identity")
      expect(ident["path"]).to eq("identity/identity.md")
    end

    it "leaves custom zone names alone" do
      File.write(manifest_path, <<~YAML)
        version: textus/2
        zones:
          - { name: research, writable_by: [human] }
          - { name: canon,    writable_by: [human] }
        entries:
          - { key: research.foo, path: research/foo.md, zone: research }
      YAML
      FileUtils.mkdir_p(File.join(root, ".textus/zones/research"))
      described_class.new(root: root).call
      yaml = YAML.load_file(manifest_path)
      names = yaml["zones"].map { |z| z["name"] }
      expect(names).to include("research", "identity")
      expect(Dir.exist?(File.join(root, ".textus/zones/research"))).to be(true)
    end

    it "rewrites the leading segment of policies[].match" do
      File.write(manifest_path, <<~YAML)
        version: textus/2
        zones:
          - { name: intake, writable_by: [script] }
        entries:
          - { key: intake.news.hn, path: intake/news/hn.md, zone: intake }
        policies:
          - match: "intake.news.*"
            refresh: { ttl: 6h, on_stale: refresh }
          - match: "intake.news.hn"
            refresh: { ttl: 1h, on_stale: warn }
      YAML
      described_class.new(root: root).call
      yaml = YAML.load_file(manifest_path)
      matches = yaml["policies"].map { |p| p["match"] }
      expect(matches).to contain_exactly("inbox.news.*", "inbox.news.hn")
    end

    it "is idempotent — a second pass produces no changes" do
      described_class.new(root: root).call
      changes = described_class.new(root: root).call
      expect(changes).to be_empty
    end

    it "leaves .textus/audit.log untouched (historical rows reference old zones)" do
      audit_path = File.join(root, ".textus/audit.log")
      File.write(audit_path, %({"verb":"put","key":"intake.news.hn"}\n))
      described_class.new(root: root).call
      expect(File.read(audit_path)).to include("intake.news.hn")
    end

    it "supports --dry-run: returns changes but does not write" do
      original = File.read(manifest_path)
      changes = described_class.new(root: root, dry_run: true).call
      expect(changes).not_to be_empty
      expect(File.read(manifest_path)).to eq(original)
      expect(Dir.exist?(File.join(root, ".textus/zones/canon"))).to be(true)
    end
  end
end
