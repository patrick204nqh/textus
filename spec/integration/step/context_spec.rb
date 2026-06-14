require "spec_helper"

RSpec.describe Textus::Step::Context do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }
  let(:ops)   { store.as("agent", correlation_id: SecureRandom.uuid) }
  let(:ctx)   { described_class.new(scope: ops) }

  before do
    FileUtils.mkdir_p(File.join(root, "data/proposals"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: proposals, kind: queue }
      entries:
        - { key: proposals.notes, path: data/proposals/notes.md, lane: proposals, owner: agent, kind: leaf}

    YAML
  end

  it "exposes get/put/audit through Operations (so authz + audit fire)" do
    ctx.put("proposals.notes", body: "hello")
    env = ctx.get("proposals.notes")
    expect(env.body.chomp).to eq("hello")
  end

  it "does NOT expose the raw store" do
    expect(ctx).not_to respond_to(:store)
    expect(ctx).not_to respond_to(:file_store)
  end

  it "exposes the role and correlation_id of the originating ctx" do
    expect(ctx.role).to eq("agent")
    expect(ctx.correlation_id).to be_a(String)
  end

  it "publish_followup routes through the bus with the same ctx" do
    seen = nil
    store.steps.on(:entry_written, :spy) { |key:, **| seen = key }
    ctx.publish_followup(:entry_written, key: "proposals.notes", envelope: nil)
    expect(seen).to eq("proposals.notes")
  end

  it "ctx.get is a pure read that never ingests (ADR 0089)" do
    # get itself no longer reads-through; a hook observing a stale entry sees it
    # stale and triggers no ingest. Writing then reading back returns the bytes
    # unchanged, and no fetch worker is constructed.
    allow(Textus::Dispatch::Pipeline::Acquire::Intake).to receive(:new).and_call_original
    ctx.put("proposals.notes", body: "hello")
    env = ctx.get("proposals.notes")
    expect(env.body.chomp).to eq("hello")
    expect(Textus::Dispatch::Pipeline::Acquire::Intake).not_to have_received(:new)
  end
end
