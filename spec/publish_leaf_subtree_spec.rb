require "spec_helper"

RSpec.describe "publish_each directory leaves (ADR 0046)" do
  include_context "textus_store_fixture"

  def write_manifest(entries_yaml)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
      #{entries_yaml}
    YAML
  end

  def skills_entry(extra = "")
    <<~Y
      - key: knowledge.skills
        kind: nested
        path: knowledge/skills
        zone: knowledge
        schema: null
        nested: true
        index_filename: SKILL.md
        publish_each: "skills/{leaf}"
      #{extra}
    Y
  end

  def write_file(rel, contents)
    abs = File.join(root, "zones/knowledge", rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, contents)
  end

  describe "enumeration: shallowest index wins" do
    it "treats a SKILL.md inside a leaf's subtree as payload, not a second leaf" do
      write_manifest(skills_entry)
      write_file("skills/my-skill/SKILL.md", "---\nname: my-skill\n---\nbody\n")
      write_file("skills/my-skill/references/SKILL.md", "nested index, not a leaf\n")

      m = Textus::Manifest.load(root)
      keys = m.resolver.enumerate(prefix: "knowledge.skills").map { |r| r[:key] }
      expect(keys).to contain_exactly("knowledge.skills.my-skill")
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
      rows = envelope["published_leaves"].select { |r| r["key"] == "knowledge.skills.my-skill" }
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

  describe "prune on rebuild" do
    before do
      write_manifest(skills_entry)
      write_file("skills/my-skill/SKILL.md", "---\nname: my-skill\n---\nbody\n")
      write_file("skills/my-skill/references/foo.md", "foo\n")
    end

    it "deletes a managed file when its source is removed, and reports it in 'pruned'" do
      repo_root = File.dirname(root)
      store = Textus::Store.new(root)
      store.as("automation").publish
      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/foo.md"))).to be true

      File.delete(File.join(root, "zones/knowledge/skills/my-skill/references/foo.md"))
      envelope = store.as("automation").publish

      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/foo.md"))).to be false
      expect(File.exist?(File.join(root, "sentinels/skills/my-skill/references/foo.md.textus-managed.json"))).to be false
      expect(envelope["pruned"]).to include(File.join(repo_root, "skills/my-skill/references/foo.md"))
    end

    it "never deletes an unmanaged file a human placed in the target tree" do
      repo_root = File.dirname(root)
      store = Textus::Store.new(root)
      store.as("automation").publish

      human_file = File.join(repo_root, "skills/my-skill/NOTES.md")
      File.write(human_file, "hand-written\n")
      store.as("automation").publish

      expect(File.exist?(human_file)).to be true
    end

    it "prunes only within the rebuilt leaf, leaving sibling leaves untouched" do
      write_file("skills/other-skill/SKILL.md", "---\nname: other-skill\n---\nx\n")
      write_file("skills/other-skill/refs/keep.md", "keep\n")
      repo_root = File.dirname(root)
      store = Textus::Store.new(root)
      store.as("automation").publish
      expect(File.exist?(File.join(repo_root, "skills/other-skill/refs/keep.md"))).to be true

      File.delete(File.join(root, "zones/knowledge/skills/my-skill/references/foo.md"))
      store.as("automation").publish

      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/foo.md"))).to be false
      expect(File.exist?(File.join(repo_root, "skills/other-skill/refs/keep.md"))).to be true
    end
  end
end
