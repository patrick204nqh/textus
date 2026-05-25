require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Accept do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones/working/network/org"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones/review"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: review, write_policy: [agent, human] }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true }
        - { key: review,             path: review,             zone: review, schema: null, owner: o, nested: true }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "applies the proposal target action and deletes the review entry" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      store.put("review.2026-05-19-add-bob",
                meta: {
                  "name" => "2026-05-19-add-bob",
                  "proposal" => { "target_key" => "working.network.org.bob", "action" => "put" },
                  "frontmatter" => { "name" => "bob", "org" => "acme" },
                },
                body: "Proposed",
                as: "agent")

      ctx = Textus::Application::Context.new(store: store, role: "human")
      result = described_class.new(ctx: ctx, bus: store.bus).call("review.2026-05-19-add-bob")

      expect(result["target_key"]).to eq("working.network.org.bob")
      expect(result["action"]).to eq("put")
      expect(result["accepted"]).to eq("review.2026-05-19-add-bob")
      expect(File.exist?(File.join(root, ".textus/zones/working/network/org/bob.md"))).to be true
      expect(File.exist?(File.join(root, ".textus/zones/review/2026-05-19-add-bob.md"))).to be false
    end
  end

  it "raises ProposalError when role is not human" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      store.put("review.foo",
                meta: {
                  "name" => "foo",
                  "proposal" => { "target_key" => "working.network.org.x", "action" => "put" },
                  "frontmatter" => { "name" => "x" },
                },
                body: "", as: "agent")

      ctx = Textus::Application::Context.new(store: store, role: "agent")
      expect { described_class.new(ctx: ctx, bus: store.bus).call("review.foo") }
        .to raise_error(Textus::ProposalError, /human/)
    end
  end

  it "fires :accepted event with correlation_id" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      store.put("review.p1",
                meta: {
                  "name" => "p1",
                  "proposal" => { "target_key" => "working.network.org.alice", "action" => "put" },
                  "frontmatter" => { "name" => "alice" },
                },
                body: "Alice content",
                as: "agent")

      ctx = Textus::Application::Context.new(store: store, role: "human", correlation_id: "corr-accept-1")
      events = []
      store.bus.subscribe(:accepted, :capture_accept) do |key:, target_key:, correlation_id:, **|
        events << { key: key, target_key: target_key, correlation_id: correlation_id }
      end

      described_class.new(ctx: ctx, bus: store.bus).call("review.p1")

      expect(events.length).to eq(1)
      expect(events.first[:key]).to eq("review.p1")
      expect(events.first[:target_key]).to eq("working.network.org.alice")
      expect(events.first[:correlation_id]).to eq("corr-accept-1")
    end
  end

  it "raises ProposalError when entry has no proposal block" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      store.put("review.noproposal",
                meta: { "name" => "noproposal" },
                body: "no proposal here",
                as: "agent")

      ctx = Textus::Application::Context.new(store: store, role: "human")
      expect { described_class.new(ctx: ctx, bus: store.bus).call("review.noproposal") }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end
end
