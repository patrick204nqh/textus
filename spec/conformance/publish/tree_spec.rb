require "spec_helper"

RSpec.describe "publish_tree (ADR 0047)" do
  include_context "textus_store_fixture"

  def write_manifest(entries_yaml)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: working, kind: canon }
      entries:
      #{entries_yaml}
    YAML
  end

  def write_file(rel, contents)
    abs = File.join(root, "data/working", rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, contents)
  end

  # Runs a full convergence pass (`converge_now`: explicit seed + queue-burn drain).
  # publish_tree
  # mirroring is a side effect of the produce phase, so tests assert on the
  # published files ON DISK rather than a result shape.
  def materialize(s = Textus::Store.new(root))
    converge_now(s)
  end

  describe "manifest wiring" do
    it "exposes publish_tree on the loaded nested entry" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          lane: working
          schema: null
          nested: true
          publish:
            - { tree: "skills" }
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
          lane: working
          schema: null
          nested: true
          publish:
            - { tree: "skills" }
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

      expect(File.exist?(File.join(root, ".state/tracking/sentinels/skills/my-skill/commands.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, ".state/tracking/sentinels/skills/my-skill/scripts/build.py.textus-managed.json"))).to be true
    end

    it "mirrors every leaf file under the published tree on disk" do
      repo_root = File.dirname(root)
      materialize
      mirrored = Dir.glob(File.join(repo_root, "skills/**/*")).select { |p| File.file?(p) }
      expect(mirrored.map { |p| File.basename(p) })
        .to contain_exactly("commands.md", "foo.md", "build.py")
    end
  end

  describe "ignore + safety" do
    it "excludes files matching the entry's ignore globs" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          lane: working
          schema: null
          nested: true
          publish:
            - { tree: "skills" }
          ignore: ["**/*.tmp"]
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      write_file("skills/my-skill/scratch.tmp", "junk\n")

      repo_root = File.dirname(root)
      materialize

      expect(File.exist?(File.join(repo_root, "skills/my-skill/commands.md"))).to be true
      expect(File.exist?(File.join(repo_root, "skills/my-skill/scratch.tmp"))).to be false
    end

    it "isolates a produce failure (does not raise) when the target escapes repo root" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          lane: working
          schema: null
          nested: true
          publish:
            - { tree: "../outside" }
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")

      store = Textus::Store.new(root)
      expect { materialize(store) }.not_to raise_error
    end
  end

  describe "prune on rebuild" do
    before do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          lane: working
          schema: null
          nested: true
          publish:
            - { tree: "skills" }
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      write_file("skills/my-skill/references/foo.md", "foo\n")
    end

    it "deletes a managed file from the published tree when its source is removed" do
      repo_root = File.dirname(root)
      store = Textus::Store.new(root)
      materialize(store)
      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/foo.md"))).to be true

      File.delete(File.join(root, "data/working/skills/my-skill/references/foo.md"))
      materialize(store)

      expect(File.exist?(File.join(repo_root, "skills/my-skill/references/foo.md"))).to be false
      expect(File.exist?(File.join(root, ".state/tracking/sentinels/skills/my-skill/references/foo.md.textus-managed.json"))).to be false
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
      Textus::Port::SentinelStore.new.write!(target: target, source: target, store_root: root)
      target
    end

    it "does NOT prune a managed file matched by the tree's ignore" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          lane: working
          schema: null
          nested: true
          publish:
            - { tree: "skills" }
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
          lane: working
          schema: null
          nested: true
          publish:
            - { tree: "skills" }
      Y
      write_file("skills/my-skill/commands.md", "# commands\n")
      repo_root = File.dirname(root)
      index = seed_managed_file(repo_root, "skills/my-skill/SKILL.md", "derived index\n")

      materialize

      expect(File.exist?(index)).to be false
    end
  end

  # ADR 0047 — publish_tree mirrors opaque payload by path; its files are never
  # addressable keys. Regression guard: neither doctor's IllegalKeys nor the
  # resolver may key-walk them, so a publish_tree subtree carrying non-key-legal
  # filenames (uppercase SKILL.md, README) must stay doctor-green and still
  # mirror. The Publisher always honored opacity; these two paths did not until
  # the `Publish::Mode#keyless?` guard.
  describe "opacity (ADR 0047)" do
    let(:opacity_manifest) do
      <<~YAML
        version: textus/4
        lanes:
          - { name: working, kind: canon }
        entries:
          - key: working.published
            path: working/skills
            lane: working
            owner: human:self
            kind: nested
            nested: true
            publish:
              - { tree: "skills" }
      YAML
    end

    let(:opacity_files) do
      {
        "data/working/skills/my-skill/SKILL.md" => "# my skill\n",
        "data/working/skills/my-skill/README.md" => "# readme\n",
        "data/working/skills/my-skill/references/algo.md" => "notes\n",
      }
    end

    let(:opacity_store) do
      store_from_manifest(root, lanes: %w[working], manifest: opacity_manifest, files: opacity_files)
    end

    it "does not flag uppercase filenames under a publish_tree entry (doctor green)" do
      issues = Textus::Doctor::Check::IllegalKeys.new(opacity_store.container).call
      expect(issues).to be_empty
    end

    it "does not enumerate publish_tree files as keys" do
      keys = opacity_store.container.manifest.resolver.enumerate.map { |r| r[:key] }
      expect(keys).to be_empty
    end

    it "still mirrors the whole subtree, uppercase files included" do
      repo_root = File.dirname(root)
      converge_now(opacity_store)

      expect(File.read(File.join(repo_root, "skills/my-skill/SKILL.md"))).to eq("# my skill\n")
      expect(File.read(File.join(repo_root, "skills/my-skill/README.md"))).to eq("# readme\n")
      expect(File.read(File.join(repo_root, "skills/my-skill/references/algo.md"))).to eq("notes\n")
    end

    it "still flags illegal segments on a non-publish nested entry (guard not over-broad)" do
      plain = <<~YAML
        version: textus/4
        lanes:
          - { name: working, kind: canon }
        entries:
          - key: working.notes
            path: working/notes
            lane: working
            owner: human:self
            kind: nested
            nested: true
      YAML
      plain_store = store_from_manifest(
        root, lanes: %w[working], manifest: plain,
              files: { "data/working/notes/Bad_Dir/note.md" => "x\n" }
      )
      issues = Textus::Doctor::Check::IllegalKeys.new(plain_store.container).call
      expect(issues).to include(hash_including("code" => "key.illegal"))
    end
  end
end
