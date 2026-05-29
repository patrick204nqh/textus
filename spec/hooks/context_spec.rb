require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Hooks::Context do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }
  let(:ops)   { store.as("agent", correlation_id: SecureRandom.uuid) }
  let(:ctx)   { described_class.new(scope: ops) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: origin, write_policy: [human, agent] }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: agent, kind: leaf}

    YAML
  end

  it "exposes get/put/audit through Operations (so authz + audit fire)" do
    ctx.put("working.notes", body: "hello")
    env = ctx.get("working.notes")
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
    store.events.register(:entry_put, :spy) { |key:, **| seen = key }
    ctx.publish_followup(:entry_put, key: "working.notes", envelope: nil)
    expect(seen).to eq("working.notes")
  end
end
