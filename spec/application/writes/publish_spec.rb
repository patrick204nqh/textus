require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Publish do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  def write_manifest(yaml)
    File.write(File.join(root, "manifest.yaml"), yaml)
  end

  context "with two nested leaves under publish_each" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/working/agents"))
      write_manifest(<<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner, builder] }
        entries:
          - key: working.agents
            path: working/agents
            zone: working
            schema: null
            owner: human:self
            nested: true
            publish_each: "agents/{basename}.md"
      YAML
      File.write(File.join(root, "zones/working/agents/alice.md"),
                 "---\nname: alice\n---\nbody\n")
      File.write(File.join(root, "zones/working/agents/bob.md"),
                 "---\nname: bob\n---\nbody\n")
    end

    it "publishes each nested leaf to its publish_each target" do
      events = []
      store.registry.register(:file_published, :cap) { |key:, target:, **| events << [key, target] }

      ctx = Textus::Application::Context.new(store: store, role: "builder")
      res = described_class.new(ctx: ctx, bus: store.bus).call

      expect(res["protocol"]).to eq(Textus::PROTOCOL)
      expect(res["published_leaves"].length).to eq(2)
      keys = res["published_leaves"].map { |r| r["key"] }
      expect(keys).to contain_exactly("working.agents.alice", "working.agents.bob")
      expect(events.length).to eq(2)
    end

    it "filters by prefix" do
      ctx = Textus::Application::Context.new(store: store, role: "builder")
      res = described_class.new(ctx: ctx, bus: store.bus).call(prefix: "working.agents.alice")
      expect(res["published_leaves"].map { |r| r["key"] }).to eq(["working.agents.alice"])
    end
  end

  context "with a publish_each target that escapes the repo root" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/working/bad"))
      write_manifest(<<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner, builder] }
        entries:
          - key: working.bad
            path: working/bad
            zone: working
            schema: null
            owner: human:self
            nested: true
            publish_each: "../../../etc/{basename}.md"
      YAML
      File.write(File.join(root, "zones/working/bad/x.md"),
                 "---\nname: x\n---\nbody\n")
    end

    it "rejects publish_each targets that escape repo root" do
      ctx = Textus::Application::Context.new(store: store, role: "builder")
      expect do
        described_class.new(ctx: ctx, bus: store.bus).call
      end.to raise_error(Textus::PublishError, /escapes repo root/)
    end
  end
end
