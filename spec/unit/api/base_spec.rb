RSpec.describe Textus::API do
  include_context "textus/4 conformance fixture"

  let(:api) { described_class.new(gate: store.gate, store:) }

  it "opens a human session" do
    session = api.open_session(role: "human")
    expect(session.role).to eq("human")
    expect(session.id).to be_a(String)
  end

  it "opens an agent session with workspace" do
    session = api.open_session(role: "agent")
    env = store.get(key: "scratchpad.sessions.#{session.id}")
    expect(env).not_to be_nil
  end

  it "resumes an existing session" do
    created = api.open_session(role: "human")
    resumed = api.resume_session(id: created.id)
    expect(resumed.id).to eq(created.id)
    expect(resumed.role).to eq(created.role)
  end

  it "raises on unknown session" do
    expect { api.resume_session(id: "nonexistent") }
      .to raise_error(Textus::UsageError, /session not found/)
  end

  it "gets a stored value" do
    session = api.open_session(role: "human")
    result = api.get(key: "knowledge.intent.0001-north-star", session:)
    expect(result["body"]).to include("Intent body")
  end

  it "closes a session" do
    session = api.open_session(role: "agent")
    api.loop_for(session).first
    api.close_session(session)
    expect(api.resume_session(id: session.id).payload).to be_a(Hash)
  end

  it "returns cursor" do
    expect(api.cursor).to be_a(Integer)
  end

  it "returns boot info" do
    boot = api.boot
    expect(boot["protocol"]).to eq("textus/4")
  end

  it "lists entries" do
    session = api.open_session(role: "human")
    result = api.list(session:, lane: "knowledge")
    expect(result).to have_key("data")
  end

  it "propose requires agent session" do
    session = api.open_session(role: "human")
    result = api.propose(key: "test", data: "body", session:)
    expect(result).to have_key("key")
  end
end
