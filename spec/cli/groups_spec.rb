require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "CLI subcommand groups" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/archive"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: archive, writable_by: [human] }
      entries:
        - { key: working.note, path: working/note.md, zone: working }
    YAML
    File.write(File.join(root, "zones/working/note.md"), "---\nuid: abc123\n---\nhello\n")
  end

  after { FileUtils.remove_entry(tmp) }

  # ── key group ─────────────────────────────────────────────────────────────

  describe "textus key uid KEY" do
    it "returns the uid and prints no deprecation warning" do
      rc = run(["key", "uid", "working.note"])
      expect(rc).to eq(0)
      expect(JSON.parse(stdout.string)["uid"]).to eq("abc123")
      expect(stderr.string).to be_empty
    end
  end

  describe "textus key mv OLD NEW" do
    it "works and prints no deprecation warning" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: working, writable_by: [human, ai, script] }
        entries:
          - { key: working.note, path: working/note.md, zone: working }
          - { key: working.memo, path: working/memo.md, zone: working }
      YAML
      rc = run(["key", "mv", "working.note", "working.memo", "--as=human"])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload).to include("from_key" => "working.note", "to_key" => "working.memo")
      expect(stderr.string).to be_empty
    end
  end

  # ── flat alias mv (deprecated) ────────────────────────────────────────────

  describe "textus mv OLD NEW (deprecated flat alias)" do
    it "works and prints a deprecation warning on stderr" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: working, writable_by: [human, ai, script] }
        entries:
          - { key: working.note, path: working/note.md, zone: working }
          - { key: working.memo, path: working/memo.md, zone: working }
      YAML
      rc = run(["mv", "working.note", "working.memo", "--as=human"])
      expect(rc).to eq(0)
      expect(stderr.string).to match(/deprecated.*use 'textus key mv'.*Removed in 0\.6/i)
    end
  end

  # ── schema group ──────────────────────────────────────────────────────────

  describe "textus schema show KEY" do
    it "returns schema envelope and prints no deprecation warning" do
      rc = run(["schema", "show", "working.note"])
      expect(rc).to eq(0)
      expect(stderr.string).to be_empty
    end
  end

  describe "textus schema KEY (back-compat dotted key)" do
    it "falls through to schema show and prints a deprecation warning" do
      rc = run(["schema", "working.note"])
      expect(rc).to eq(0)
      expect(stderr.string).to match(/deprecated.*use 'textus schema show KEY'.*Removed in 0\.6/i)
    end
  end

  # ── extension group ───────────────────────────────────────────────────────

  describe "textus extension list" do
    it "lists extensions and prints no deprecation warning" do
      rc = run(%w[extension list])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload).to have_key("extensions")
      expect(stderr.string).to be_empty
    end
  end

  describe "textus extensions list (deprecated flat alias)" do
    it "works and prints a deprecation warning" do
      rc = run(%w[extensions list])
      expect(rc).to eq(0)
      expect(stderr.string).to match(/deprecated.*use 'textus extension list'.*Removed in 0\.6/i)
    end
  end

  # ── missing subcommand errors ─────────────────────────────────────────────

  describe "textus key (no subcommand)" do
    it "raises UsageError listing valid subcommands" do
      run(["key"])
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
      expect(stderr.string).to match(/key requires a subcommand:.*mv.*uid.*migrate/i)
    end
  end

  describe "textus key bogus" do
    it "raises UsageError listing valid subcommands" do
      run(%w[key bogus])
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
      expect(stderr.string).to match(/unknown key subcommand 'bogus'/i)
    end
  end
end
