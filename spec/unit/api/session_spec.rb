RSpec.describe Textus::API::Session do
  subject(:session) { described_class.new(id: "s-1", role: "agent") }

  it "has an id" do
    expect(session.id).to eq("s-1")
  end

  it "has a role" do
    expect(session.role).to eq("agent")
  end

  it "generates correlation_id when not provided" do
    expect(session.correlation_id).to be_a(String)
  end

  it "accepts explicit correlation_id" do
    s = described_class.new(id: "s-1", role: "agent", correlation_id: "cid-1")
    expect(s.correlation_id).to eq("cid-1")
  end

  it "defaults payload to empty hash" do
    expect(session.payload).to eq({})
  end

  it "accepts payload" do
    s = described_class.new(id: "s-1", role: "agent", payload: { loop_index: 3 })
    expect(s.payload).to eq({ loop_index: 3 })
  end

  it "agent? returns true for agent role" do
    expect(session.agent?).to be true
  end

  it "human? returns true for human role" do
    s = described_class.new(id: "s-1", role: "human")
    expect(s.human?).to be true
  end

  it "with_payload returns new session with same id and role" do
    updated = session.with_payload({ loop_index: 5 })
    expect(updated.payload).to eq({ loop_index: 5 })
    expect(updated.id).to eq(session.id)
    expect(updated.role).to eq(session.role)
  end
end
