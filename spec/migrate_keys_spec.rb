require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Textus::MigrateKeys do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
  end

  after { FileUtils.remove_entry(tmp) }

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, ai, script] }
      entries:
      #{entries_yaml}
    YAML
  end

  def write_md(*parts, body: "---\n---\nx")
    path = File.join(root, "zones", "working", "notes", *parts)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  describe "dry-run plan" do
    before do
      write_manifest("  - { key: working.notes, path: working/notes, zone: working, nested: true }")
      write_md("Some_File.md")
      write_md("BadName.md")
      write_md("legal-name.md")
    end

    it "proposes renames for illegal stems, leaves legal ones alone, and writes nothing" do
      store = Textus::Store.new(root)
      res = described_class.run(store, write: false)

      expect(res["ok"]).to be true
      expect(res["mode"]).to eq("dry-run")
      expect(res["collisions"]).to eq([])

      tos = res["renames"].map { |r| File.basename(r["to"]) }
      expect(tos).to contain_exactly("some-file.md", "badname.md")

      new_keys = res["renames"].map { |r| r["new_key"] }
      expect(new_keys).to contain_exactly("working.notes.some-file", "working.notes.badname")

      # Nothing on disk has changed.
      expect(File.exist?(File.join(root, "zones/working/notes/Some_File.md"))).to be true
      expect(File.exist?(File.join(root, "zones/working/notes/some-file.md"))).to be false
    end
  end

  describe "collision detection" do
    before do
      write_manifest("  - { key: working.notes, path: working/notes, zone: working, nested: true }")
      write_md("Some_File.md")
      write_md("some.file.md")
    end

    it "reports the collision and marks ok=false even in dry-run" do
      store = Textus::Store.new(root)
      res = described_class.run(store, write: false)

      expect(res["ok"]).to be false
      expect(res["collisions"].length).to eq(1)
      coll = res["collisions"].first
      expect(File.basename(coll["target"])).to eq("some-file.md")
      expect(coll["sources"].map { |s| File.basename(s) }).to contain_exactly("Some_File.md", "some.file.md")
      # No renames recorded for the colliding pair.
      expect(res["renames"]).to be_empty
    end

    it "refuses to write when collisions are present" do
      store = Textus::Store.new(root)
      res = described_class.run(store, write: true)

      expect(res["ok"]).to be false
      # Source files are untouched.
      expect(File.exist?(File.join(root, "zones/working/notes/Some_File.md"))).to be true
      expect(File.exist?(File.join(root, "zones/working/notes/some.file.md"))).to be true
    end
  end

  describe "write mode" do
    before do
      write_manifest("  - { key: working.notes, path: working/notes, zone: working, nested: true }")
      write_md("Some_File.md", body: "---\n---\nA")
      write_md("legal-name.md", body: "---\n---\nB")
    end

    it "renames files on disk and writes audit log entries" do # rubocop:disable RSpec/MultipleExpectations
      store = Textus::Store.new(root)
      res = described_class.run(store, write: true)

      expect(res["ok"]).to be true
      expect(res["mode"]).to eq("write")
      expect(File.exist?(File.join(root, "zones/working/notes/Some_File.md"))).to be false
      expect(File.exist?(File.join(root, "zones/working/notes/some-file.md"))).to be true
      expect(File.read(File.join(root, "zones/working/notes/some-file.md"))).to eq("---\n---\nA")

      parsed_lines = File.readlines(File.join(root, "audit.log")).map { |l| JSON.parse(l.chomp) }
      migrate_lines = parsed_lines.select { |h| h["verb"] == "migrate-keys" }
      expect(migrate_lines.length).to eq(1)

      row = migrate_lines.first
      expect(row["role"]).to eq("script")
      expect(row["verb"]).to eq("migrate-keys")
      expect(row["key"]).to eq("working.notes.some-file")
      expect(row["extras"]["from"]).to end_with("/Some_File.md")
      expect(row["extras"]["to"]).to end_with("/some-file.md")
    end
  end

  describe "directory rename" do
    before do
      write_manifest("  - { key: working.notes, path: working/notes, zone: working, nested: true }")
      # Org/CMC.Global/charter.md — illegal segments at both directory levels;
      # leaf file is legal but lives under illegal parents.
      write_md("Org", "CMC.Global", "charter.md", body: "---\n---\nC")
    end

    it "renames directories too, bottom-up, and produces post-rename keys" do
      store = Textus::Store.new(root)
      res = described_class.run(store, write: true)

      expect(res["ok"]).to be true
      expect(File.exist?(File.join(root, "zones/working/notes/Org/CMC.Global/charter.md"))).to be false
      expect(File.exist?(File.join(root, "zones/working/notes/org/cmc-global/charter.md"))).to be true

      parsed_lines = File.readlines(File.join(root, "audit.log")).map { |l| JSON.parse(l.chomp) }
      migrate_lines = parsed_lines.select { |h| h["verb"] == "migrate-keys" }
      # Two directories renamed: CMC.Global and Org. (charter.md is already legal.)
      expect(migrate_lines.length).to eq(2)

      keys = migrate_lines.map { |h| h["key"] }
      # Order matters: child dir is renamed before its parent dir.
      expect(keys).to eq(["working.notes.org.cmc-global", "working.notes.org"])

      # The child rename's `from` should reflect the disk path at the moment
      # of renaming (parent not yet renamed).
      expect(migrate_lines.first["extras"]["from"]).to end_with("/Org/CMC.Global")
      expect(migrate_lines.first["extras"]["to"]).to end_with("/Org/cmc-global")

      expect(migrate_lines.last["extras"]["from"]).to end_with("/notes/Org")
      expect(migrate_lines.last["extras"]["to"]).to end_with("/notes/org")
    end
  end
end
