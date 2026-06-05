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

  # Returns the Materialize envelope (published_leaves, pruned, built).
  # Use this when the test needs to inspect the result shape; use .reconcile
  # when only the side effects matter.
  def materialize(s = Textus::Store.new(root))
    call = Textus::Call.build(role: "automation")
    Textus::Maintenance::Materialize.new(container: s.container, call: call).call
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
          publish:
            tree: "skills"
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
          publish:
            tree: "skills"
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      write_file("skills/my-skill/references/foo.md", "foo reference\n")
      write_file("skills/my-skill/scripts/build.py", "print('hi')\n")
    end

    it "mirrors every file by real path, including non-markdown, with per-file sentinels" do
      repo_root = File.dirname(root)
      materialize

      expect(File.read(File.join(repo_root, "skills/my-skill/commands.md"))).to eq("# commands\n")
      expect(File.read(File.join(repo_root, "skills/my-skill/references/foo.md"))).to eq("foo reference\n")
      expect(File.read(File.join(repo_root, "skills/my-skill/scripts/build.py"))).to eq("print('hi')\n")

      expect(File.exist?(File.join(root, ".run/sentinels/skills/my-skill/commands.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, ".run/sentinels/skills/my-skill/scripts/build.py.textus-managed.json"))).to be true
    end

    it "reports every mirrored file in published_leaves under the entry key" do
      envelope = materialize
      rows = envelope["published_leaves"].select { |r| r["key"] == "working.skills" }
      expect(rows.map { |r| File.basename(r["target"]) })
        .to contain_exactly("commands.md", "foo.md", "build.py")
    end
  end

  describe "ignore + safety" do
    it "excludes files matching the entry's ignore globs" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish:
            tree: "skills"
          ignore: ["**/*.tmp"]
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      write_file("skills/my-skill/scratch.tmp", "junk\n")

      repo_root = File.dirname(root)
      materialize

      expect(File.exist?(File.join(repo_root, "skills/my-skill/commands.md"))).to be true
      expect(File.exist?(File.join(repo_root, "skills/my-skill/scratch.tmp"))).to be false
    end

    it "raises when the target escapes repo root" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish:
            tree: "../outside"
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")

      expect { materialize }
        .to raise_error(Textus::PublishError, /escapes repo root/)
    end
  end

  describe "prune on rebuild" do
    before do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish:
            tree: "skills"
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      write_file("skills/my-skill/references/foo.md", "foo\n")
    end

    it "deletes a managed file when its source is removed, and reports it in 'pruned'" do
      repo_root = File.dirname(root)
      store = Textus::Store.new(root)
      materialize(store)
      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/foo.md"))).to be true

      File.delete(File.join(root, "zones/working/skills/my-skill/references/foo.md"))
      envelope = materialize(store)

      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/foo.md"))).to be false
      expect(File.exist?(File.join(root, ".run/sentinels/skills/my-skill/references/foo.md.textus-managed.json"))).to be false
      expect(envelope["pruned"]).to include(File.join(repo_root, "skills/my-skill/references/foo.md"))
    end

    it "never deletes an unmanaged file a human placed in the target tree" do
      repo_root = File.dirname(root)
      store = Textus::Store.new(root)
      materialize(store)

      human_file = File.join(repo_root, "skills/my-skill/NOTES.md")
      File.write(human_file, "hand-written\n")
      materialize(store)

      expect(File.exist?(human_file)).to be true
    end
  end

  describe "prune honors ignore for a foreign managed file (ADR 0047 D4)" do
    def seed_managed_file(repo_root, rel, body)
      target = File.join(repo_root, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, body)
      Textus::Ports::SentinelStore.new.write!(target: target, source: target, store_root: root)
      target
    end

    it "does NOT prune a managed file matched by the tree's ignore" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish:
            tree: "skills"
          ignore: ["**/SKILL.md"]
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      repo_root = File.dirname(root)
      index = seed_managed_file(repo_root, "skills/my-skill/SKILL.md", "derived index\n")

      materialize

      expect(File.exist?(index)).to be true
      expect(File.read(File.join(repo_root, "skills/my-skill/commands.md"))).to eq("# commands\n")
    end

    it "DOES prune the same managed file when the tree does not ignore it" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish:
            tree: "skills"
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      repo_root = File.dirname(root)
      index = seed_managed_file(repo_root, "skills/my-skill/SKILL.md", "derived index\n")

      envelope = materialize

      expect(File.exist?(index)).to be false
      expect(envelope["pruned"]).to include(index)
    end
  end
end
