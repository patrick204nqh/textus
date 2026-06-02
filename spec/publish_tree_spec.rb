require "spec_helper"

RSpec.describe "publish_tree (ADR 0047)" do
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

  def write_file(rel, contents)
    abs = File.join(root, "zones/working", rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, contents)
  end

  describe "manifest wiring" do
    it "exposes publish_tree on the loaded nested entry" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish_tree: "skills"
      Y

      m = Textus::Manifest.load(root)
      entry = m.data.entries.find { |e| e.key == "working.skills" }
      expect(entry.publish_tree).to eq("skills")
    end
  end

  describe "subtree mirror" do
    before do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish_tree: "skills"
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      write_file("skills/my-skill/references/foo.md", "foo reference\n")
      write_file("skills/my-skill/scripts/build.py", "print('hi')\n")
    end

    it "mirrors every file by real path, including non-markdown, with per-file sentinels" do
      repo_root = File.dirname(root)
      Textus::Store.new(root).as("automation").publish

      expect(File.read(File.join(repo_root, "skills/my-skill/commands.md"))).to eq("# commands\n")
      expect(File.read(File.join(repo_root, "skills/my-skill/references/foo.md"))).to eq("foo reference\n")
      expect(File.read(File.join(repo_root, "skills/my-skill/scripts/build.py"))).to eq("print('hi')\n")

      expect(File.exist?(File.join(root, "sentinels/skills/my-skill/commands.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, "sentinels/skills/my-skill/scripts/build.py.textus-managed.json"))).to be true
    end

    it "reports every mirrored file in published_leaves under the entry key" do
      envelope = Textus::Store.new(root).as("automation").publish
      rows = envelope["published_leaves"].select { |r| r["key"] == "working.skills" }
      expect(rows.map { |r| File.basename(r["target"]) })
        .to contain_exactly("commands.md", "foo.md", "build.py")
    end
  end
end
