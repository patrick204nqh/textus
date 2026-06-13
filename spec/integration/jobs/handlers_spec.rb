require "spec_helper"

RSpec.describe Textus::Jobs::Handlers do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
    YAML
  end
  let(:registry) { described_class.registry }

  it "registers the closed convergence type set" do
    %w[materialize re-pull sweep].each do |type|
      expect(registry.registered?(type)).to be true
    end
  end

  it "gates ad-hoc sweep enqueue to automation; produce is open to any caller" do
    expect(registry.lookup("sweep").required_role).to eq("automation")
    expect(registry.lookup("materialize").required_role).to be_nil
  end

  it "materialize runs Produce::Engine.converge for the job's key" do
    allow(Textus::Produce::Engine).to receive(:converge)
    job = Textus::Core::Jobs::Job.new(type: "materialize", args: { "key" => "k.x" }, enqueued_by: "automation")
    registry.lookup("materialize").handler.call(job: job, container: store.container)
    expect(Textus::Produce::Engine).to have_received(:converge).with(hash_including(keys: ["k.x"]))
  end

  it "sweep runs as the job's stamped role, not self-elevated" do
    job = Textus::Core::Jobs::Job.new(type: "sweep", args: { "scope" => nil }, enqueued_by: "human")
    captured = nil
    allow(Textus::Maintenance::Retention::Apply).to receive(:new) do |call:, **|
      captured = call.role
      instance_double(Textus::Maintenance::Retention::Apply, call: { dropped: [], archived: [], failed: [] })
    end
    registry.lookup("sweep").handler.call(job: job, container: store.container)
    expect(captured).to eq("human")
  end
end
