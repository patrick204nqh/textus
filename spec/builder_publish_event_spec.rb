require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Builder fires :publish per file" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "zones/working/agents"))
    FileUtils.mkdir_p(File.join(root, "templates"))
  end

  after { FileUtils.remove_entry(tmp) }

  describe "publish_to: fires :publish once per target path" do
    before do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: working, writable_by: [human, ai, script] }
          - { name: derived, writable_by: [build] }
        entries:
          - { key: working.note, path: working/note.md, zone: working, schema: null }
          - key: derived.note
            path: derived/note.md
            zone: derived
            schema: null
            owner: build:auto
            projection: { select: working.note }
            template: echo.mustache
            publish_to:
              - out/one.md
              - out/two.md
      YAML

      File.write(File.join(root, "templates/echo.mustache"), "hello {{key}}\n")
      File.write(File.join(root, "zones/working/note.md"),
                 "---\nkey: working.note\n---\nbody\n")
    end

    it "fires :publish once per publish_to target with correct key/source/target" do
      captured = []
      store.registry.register(:published, :capture) do |key:, envelope:, source:, target:, **|
        _ = envelope
        captured << { key: key, source: source, target: target }
      end

      Textus::Builder.new(store).build(prefix: "derived.note")

      expect(captured.size).to eq(2)
      expect(captured.map { _1[:key] }).to all(eq("derived.note"))

      targets = captured.map { _1[:target] }
      expect(targets).to include(File.join(tmp, "out/one.md"))
      expect(targets).to include(File.join(tmp, "out/two.md"))

      sources = captured.map { _1[:source] }
      expect(sources).to all(end_with("derived/note.md"))
    end

    it "fires :build exactly once per derived entry regardless of publish_to count" do
      build_events = []
      store.registry.register(:built, :capture_build) do |key:, envelope:, sources:, **|
        _ = envelope
        build_events << { key: key, sources: sources }
      end

      Textus::Builder.new(store).build(prefix: "derived.note")

      expect(build_events.size).to eq(1)
      expect(build_events.first[:key]).to eq("derived.note")
    end
  end

  describe "publish_each: fires :publish once per leaf" do
    before do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: working, writable_by: [human, ai, script] }
        entries:
          - key: working.agents
            path: working/agents
            zone: working
            schema: null
            nested: true
            publish_each: "agents/{basename}.md"
      YAML

      File.write(File.join(root, "zones/working/agents/alpha.md"),
                 "---\nname: alpha\n---\nbody\n")
      File.write(File.join(root, "zones/working/agents/beta.md"),
                 "---\nname: beta\n---\nbody\n")
    end

    it "fires :publish once per leaf with the correct leaf key and target" do
      captured = []
      store.registry.register(:published, :capture_leaf) do |key:, envelope:, source:, target:, **|
        _ = envelope
        captured << { key: key, source: source, target: target }
      end

      Textus::Builder.new(store).build

      expect(captured.size).to eq(2)
      keys = captured.map { _1[:key] }
      expect(keys).to contain_exactly("working.agents.alpha", "working.agents.beta")

      targets = captured.map { _1[:target] }
      expect(targets).to include(File.join(tmp, "agents/alpha.md"))
      expect(targets).to include(File.join(tmp, "agents/beta.md"))
    end
  end
end
