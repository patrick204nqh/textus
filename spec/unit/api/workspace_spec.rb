RSpec.describe Textus::API::Workspace do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(File.join(root, "data/scratchpad/sessions"))
    store_from_manifest(root, lanes: %w[scratchpad], files: {}, manifest: <<~YAML)
      version: textus/4
      data:
        scratchpad:
          - key: scratchpad.sessions
      YAML
  end

  subject(:workspace) { described_class.new(store) }

  let(:sid) { "2026-07-09-test" }

  it "creates scratchpad entry for agent" do
    workspace.create(sid, role: "agent")
    env = store.get(key: "scratchpad.sessions.#{sid}")
    expect(env).not_to be_nil
    expect(JSON.parse(env["body"])["role"]).to eq("agent")
  end

  it "does nothing for non-agent" do
    workspace.create(sid, role: "human")
    expect { store.get(key: "scratchpad.sessions.#{sid}") }.to raise_error(Textus::UnknownKey)
  end

  it "closes an existing session" do
    workspace.create(sid, role: "agent")
    workspace.close(sid, loop_status: { node: "intent" })
    env = store.get(key: "scratchpad.sessions.#{sid}")
    expect(JSON.parse(env["body"])["status"]).to eq("sealed")
  end

  it "does nothing when closing nonexistent session" do
    expect { workspace.close("nonexistent") }.not_to raise_error
  end

  it "includes feedback on close" do
    workspace.create(sid, role: "agent")
    workspace.close(sid, nodes_checked: %w[intent evidence])
    env = store.get(key: "scratchpad.sessions.#{sid}")
    feedback = JSON.parse(env["body"])["feedback"]
    expect(feedback["signal"]).to eq("session_closed")
    expect(feedback["nodes_checked"]).to eq(%w[intent evidence])
  end
end
