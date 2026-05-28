require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe "publish_each:" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/agents"))
    FileUtils.mkdir_p(File.join(root, "zones/working/skills/writing"))
    FileUtils.mkdir_p(File.join(root, "zones/working/skills/research"))
    FileUtils.mkdir_p(File.join(root, "zones/working/commands"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
  end

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: output, write_policy: [builder] }
      entries:
      #{entries_yaml}
    YAML
  end

  describe "manifest validation" do
    it "raises if publish_each is set without nested: true" do
      write_manifest(
        "  - { key: working.flat, path: working/flat.md, zone: working, schema: null, kind: leaf, " \
        "publish_each: \"out/{basename}.md\" }",
      )
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /publish_each requires nested: true/)
    end

    it "raises if both publish_to and publish_each are set" do
      write_manifest(<<~Y)
        - key: working.agents
          kind: nested
          path: working/agents
          zone: working
          schema: null
          nested: true
          publish_to: [out.md]
          publish_each: "out/{basename}.md"
      Y
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /mutually exclusive/)
    end

    it "raises if the template references no leaf-derived variable" do
      write_manifest(<<~Y)
        - key: working.agents
          kind: nested
          path: working/agents
          zone: working
          schema: null
          nested: true
          publish_each: "agents/static.md"
      Y
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /must reference at least one of/)
    end

    it "raises if the template uses an unknown variable" do
      write_manifest(<<~Y)
        - key: working.agents
          kind: nested
          path: working/agents
          zone: working
          schema: null
          nested: true
          publish_each: "agents/{basename}-{bogus}.md"
      Y
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /unknown template variable.*bogus/)
    end

    it "accepts {leaf}, {basename}, {key}, {ext}" do
      write_manifest(<<~Y)
        - key: working.agents
          kind: nested
          path: working/agents
          zone: working
          schema: null
          nested: true
          publish_each: "agents/{leaf}.{ext}"
      Y
      expect { Textus::Manifest.load(root) }.not_to raise_error
    end
  end

  describe "publish_target_for" do
    it "substitutes {leaf}, {basename}, {key}, {ext} correctly for a deep tree" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish_each: "out/{leaf}/k={key}/b={basename}.{ext}"
      Y
      m = Textus::Manifest.load(root)
      entry = m.data.entries.first
      target = entry.publish_target_for("working.skills.writing.voice-writer")
      expect(target).to eq("out/writing/voice-writer/k=working.skills.writing.voice-writer/b=voice-writer.md")
    end
  end

  describe "Builder publishes every leaf" do
    def write_skill(path, name)
      File.write(File.join(root, "zones/working", path), <<~MD)
        ---
        name: #{name}
        ---
        body for #{name}
      MD
    end

    before do
      write_manifest(<<~Y)
        - key: working.agents
          kind: nested
          path: working/agents
          zone: working
          schema: null
          nested: true
          publish_each: "agents/{basename}.md"

        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish_each: "skills/{basename}/SKILL.md"

        - key: working.commands
          kind: nested
          path: working/commands
          zone: working
          schema: null
          nested: true
          publish_each: "commands/{basename}.md"
      Y

      write_skill("agents/voice-writer.md", "voice-writer")
      write_skill("agents/fact-checker.md", "fact-checker")
      write_skill("skills/writing/voice-writer.md", "voice-writer")
      write_skill("skills/research/fact-checker.md", "fact-checker")
      write_skill("commands/rewrite.md", "rewrite")
    end

    it "publishes one file per leaf with sentinels under .textus/sentinels/" do
      store = Textus::Store.new(root)
      envelope = store.session(role: "builder").publish

      expect(envelope["published_leaves"].size).to eq(5)

      repo_root = File.dirname(root)
      expect(File.exist?(File.join(repo_root, "agents/voice-writer.md"))).to be true
      expect(File.exist?(File.join(repo_root, "agents/fact-checker.md"))).to be true
      expect(File.exist?(File.join(repo_root, "skills/voice-writer/SKILL.md"))).to be true
      expect(File.exist?(File.join(repo_root, "skills/fact-checker/SKILL.md"))).to be true
      expect(File.exist?(File.join(repo_root, "commands/rewrite.md"))).to be true

      # byte-identical copies
      src = File.join(root, "zones/working/agents/voice-writer.md")
      dst = File.join(repo_root, "agents/voice-writer.md")
      expect(File.binread(src)).to eq(File.binread(dst))

      # sentinels live under .textus/sentinels/
      expect(File.exist?(File.join(root, "sentinels/agents/voice-writer.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, "sentinels/skills/voice-writer/SKILL.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, "sentinels/commands/rewrite.md.textus-managed.json"))).to be true
    end

    it "prefix: filter limits which leaves get published" do
      store = Textus::Store.new(root)
      envelope = store.session(role: "builder").publish(prefix: "working.agents")
      keys = envelope["published_leaves"].map { |r| r["key"] }
      expect(keys).to contain_exactly("working.agents.voice-writer", "working.agents.fact-checker")
    end
  end

  describe "path-escape defense" do
    it "refuses to publish to a target outside the repo root" do
      write_manifest(<<~Y)
        - key: working.agents
          kind: nested
          path: working/agents
          zone: working
          schema: null
          nested: true
          publish_each: "../../{basename}.md"
      Y
      File.write(File.join(root, "zones/working/agents/x.md"), "---\nname: x\n---\n")

      store = Textus::Store.new(root)
      expect { store.session(role: "builder").publish }
        .to raise_error(Textus::PublishError, /escapes repo root/)
    end
  end
end
