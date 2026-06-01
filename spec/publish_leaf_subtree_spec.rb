require "spec_helper"

RSpec.describe "publish_each directory leaves (ADR 0046)" do
  include_context "textus_store_fixture"

  def write_manifest(entries_yaml)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
      #{entries_yaml}
    YAML
  end

  def skills_entry(extra = "")
    <<~Y
      - key: working.skills
        kind: nested
        path: working/skills
        zone: working
        schema: null
        nested: true
        index_filename: SKILL.md
        publish_each: "skills/{leaf}"
      #{extra}
    Y
  end

  def write_file(rel, contents)
    abs = File.join(root, "zones/working", rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, contents)
  end

  describe "enumeration: shallowest index wins" do
    it "treats a SKILL.md inside a leaf's subtree as payload, not a second leaf" do
      write_manifest(skills_entry)
      write_file("skills/my-skill/SKILL.md", "---\nname: my-skill\n---\nbody\n")
      write_file("skills/my-skill/references/SKILL.md", "nested index, not a leaf\n")

      m = Textus::Manifest.load(root)
      keys = m.resolver.enumerate(prefix: "working.skills").map { |r| r[:key] }
      expect(keys).to contain_exactly("working.skills.my-skill")
    end
  end

  describe "subtree publish" do
    before do
      write_manifest(skills_entry)
      write_file("skills/my-skill/SKILL.md", "---\nname: my-skill\n---\nbody\n")
      write_file("skills/my-skill/commands.md", "# commands\n")
      write_file("skills/my-skill/references/foo.md", "foo reference\n")
    end

    it "publishes the entire leaf directory, preserving layout, with per-file sentinels" do
      repo_root = File.dirname(root)
      Textus::Store.new(root).as("automation").publish

      expect(File.read(File.join(repo_root, "skills/my-skill/SKILL.md"))).to include("name: my-skill")
      expect(File.read(File.join(repo_root, "skills/my-skill/commands.md"))).to eq("# commands\n")
      expect(File.read(File.join(repo_root, "skills/my-skill/references/foo.md"))).to eq("foo reference\n")

      expect(File.exist?(File.join(root, "sentinels/skills/my-skill/SKILL.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, "sentinels/skills/my-skill/commands.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, "sentinels/skills/my-skill/references/foo.md.textus-managed.json"))).to be true
    end

    it "reports every published file in published_leaves under the leaf key" do
      envelope = Textus::Store.new(root).as("automation").publish
      rows = envelope["published_leaves"].select { |r| r["key"] == "working.skills.my-skill" }
      expect(rows.map { |r| File.basename(r["target"]) }).to contain_exactly("SKILL.md", "commands.md", "foo.md")
    end

    it "excludes files matching the entry's ignore globs" do
      write_manifest(skills_entry("  ignore: [\"**/*.tmp\"]"))
      write_file("skills/my-skill/references/scratch.tmp", "junk\n")

      repo_root = File.dirname(root)
      Textus::Store.new(root).as("automation").publish

      expect(File.exist?(File.join(repo_root, "skills/my-skill/SKILL.md"))).to be true
      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/scratch.tmp"))).to be false
    end
  end
end
