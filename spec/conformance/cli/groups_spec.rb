require "spec_helper"

RSpec.describe "CLI subcommand groups" do
  include_context "textus_store_fixture"
  include_context "cli invocation"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/archive"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: archive, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, zone: knowledge, kind: leaf}

    YAML
    File.write(File.join(root, "data/knowledge/note.md"), "---\nuid: abc123\n---\nhello\n")
  end

  # ── key group ─────────────────────────────────────────────────────────────

  describe "textus key uid KEY" do
    it "returns the uid and prints no deprecation warning" do
      rc = run(["key", "uid", "knowledge.note"])
      expect(rc).to eq(0)
      expect(JSON.parse(stdout.string)["uid"]).to eq("abc123")
      expect(stderr.string).to be_empty
    end
  end

  describe "textus key mv OLD NEW" do
    it "works and prints no deprecation warning" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.note, path: knowledge/note.md, zone: knowledge, kind: leaf}

          - { key: knowledge.memo, path: knowledge/memo.md, zone: knowledge, kind: leaf}

      YAML
      rc = run(["key", "mv", "knowledge.note", "knowledge.memo", "--as=human"])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload).to include("from_key" => "knowledge.note", "to_key" => "knowledge.memo")
      expect(stderr.string).to be_empty
    end
  end

  # ── schema group ──────────────────────────────────────────────────────────

  describe "textus schema show KEY" do
    it "returns schema envelope and prints no deprecation warning" do
      rc = run(["schema", "show", "knowledge.note"])
      expect(rc).to eq(0)
      expect(stderr.string).to be_empty
    end
  end

  # ── missing subcommand errors ─────────────────────────────────────────────

  describe "textus key (no subcommand)" do
    it "raises UsageError listing valid subcommands" do
      run(["key"])
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
      expect(stderr.string).to match(/key requires a subcommand:.*mv.*uid/i)
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
