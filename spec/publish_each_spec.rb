require "spec_helper"

RSpec.describe "publish_each:" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/agents"))
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/skills/writing"))
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/skills/research"))
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/commands"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
  end

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: derived }
      entries:
      #{entries_yaml}
    YAML
  end

  describe "manifest validation" do
    it "raises if publish_each is set without nested: true" do
      write_manifest(
        "  - { key: knowledge.flat, path: knowledge/flat.md, zone: knowledge, kind: leaf, " \
        "publish_each: \"out/{basename}.md\" }",
      )
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /publish_each requires nested: true/)
    end

    it "raises if both publish_to and publish_each are set" do
      write_manifest(<<~Y)
        - key: knowledge.agents
          kind: nested
          path: knowledge/agents
          zone: knowledge
          publish_to: [out.md]
          publish_each: "out/{basename}.md"
      Y
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /mutually exclusive/)
    end

    it "raises if the template references no leaf-derived variable" do
      write_manifest(<<~Y)
        - key: knowledge.agents
          kind: nested
          path: knowledge/agents
          zone: knowledge
          publish_each: "agents/static.md"
      Y
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /must reference at least one of/)
    end

    it "raises if the template uses an unknown variable" do
      write_manifest(<<~Y)
        - key: knowledge.agents
          kind: nested
          path: knowledge/agents
          zone: knowledge
          publish_each: "agents/{basename}-{bogus}.md"
      Y
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /unknown template variable.*bogus/)
    end

    it "accepts {leaf}, {basename}, {key}, {ext}" do
      write_manifest(<<~Y)
        - key: knowledge.agents
          kind: nested
          path: knowledge/agents
          zone: knowledge
          publish_each: "agents/{leaf}.{ext}"
      Y
      expect { Textus::Manifest.load(root) }.not_to raise_error
    end
  end

  describe "publish_target_for" do
    it "substitutes {leaf}, {basename}, {key}, {ext} correctly for a deep tree" do
      write_manifest(<<~Y)
        - key: knowledge.skills
          kind: nested
          path: knowledge/skills
          zone: knowledge
          publish_each: "out/{leaf}/k={key}/b={basename}.{ext}"
      Y
      m = Textus::Manifest.load(root)
      entry = m.data.entries.first
      target = entry.publish_target_for("knowledge.skills.writing.voice-writer")
      expect(target).to eq("out/writing/voice-writer/k=knowledge.skills.writing.voice-writer/b=voice-writer.md")
    end
  end

  describe "Builder publishes every leaf" do
    def write_skill(path, name)
      File.write(File.join(root, "zones/knowledge", path), <<~MD)
        ---
        name: #{name}
        ---
        body for #{name}
      MD
    end

    before do
      write_manifest(<<~Y)
        - key: knowledge.agents
          kind: nested
          path: knowledge/agents
          zone: knowledge
          publish_each: "agents/{basename}.md"

        - key: knowledge.skills
          kind: nested
          path: knowledge/skills
          zone: knowledge
          publish_each: "skills/{basename}/SKILL.md"

        - key: knowledge.commands
          kind: nested
          path: knowledge/commands
          zone: knowledge
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
      envelope = store.as("automation").publish

      expect(envelope["published_leaves"].size).to eq(5)

      repo_root = File.dirname(root)
      expect(File.exist?(File.join(repo_root, "agents/voice-writer.md"))).to be true
      expect(File.exist?(File.join(repo_root, "agents/fact-checker.md"))).to be true
      expect(File.exist?(File.join(repo_root, "skills/voice-writer/SKILL.md"))).to be true
      expect(File.exist?(File.join(repo_root, "skills/fact-checker/SKILL.md"))).to be true
      expect(File.exist?(File.join(repo_root, "commands/rewrite.md"))).to be true

      # byte-identical copies
      src = File.join(root, "zones/knowledge/agents/voice-writer.md")
      dst = File.join(repo_root, "agents/voice-writer.md")
      expect(File.binread(src)).to eq(File.binread(dst))

      # sentinels live under .textus/sentinels/
      expect(File.exist?(File.join(root, "sentinels/agents/voice-writer.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, "sentinels/skills/voice-writer/SKILL.md.textus-managed.json"))).to be true
      expect(File.exist?(File.join(root, "sentinels/commands/rewrite.md.textus-managed.json"))).to be true
    end

    it "prefix: filter limits which leaves get published" do
      store = Textus::Store.new(root)
      envelope = store.as("automation").publish(prefix: "knowledge.agents")
      keys = envelope["published_leaves"].map { |r| r["key"] }
      expect(keys).to contain_exactly("knowledge.agents.voice-writer", "knowledge.agents.fact-checker")
    end
  end

  describe "path-escape defense" do
    it "refuses to publish to a target outside the repo root" do
      write_manifest(<<~Y)
        - key: knowledge.agents
          kind: nested
          path: knowledge/agents
          zone: knowledge
          publish_each: "../../{basename}.md"
      Y
      File.write(File.join(root, "zones/knowledge/agents/x.md"), "---\nname: x\n---\n")

      store = Textus::Store.new(root)
      expect { store.as("automation").publish }
        .to raise_error(Textus::PublishError, /escapes repo root/)
    end
  end
end
