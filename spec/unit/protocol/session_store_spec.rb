RSpec.describe Textus::Protocol::SessionStore do
  subject(:store) { described_class.new(db) }
  let(:db) do
    s = Sequel.sqlite
    s.create_table(:sessions) do
      String :id, primary_key: true
      String :role, null: false
      String :surface_id
      Integer :cursor_seq
      String :contract_etag
      String :status, default: "active"
      String :correlation_id
      String :payload, text: true
      DateTime :expires_at
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
    s
  end

  it "creates a session with default fields" do
    row = store.create(id: "s-1", role: "human")
    expect(row[:id]).to eq("s-1")
    expect(row[:role]).to eq("human")
    expect(row[:status]).to eq("active")
    expect(row[:correlation_id]).to be_a(String)
    expect(row[:payload]).to eq({})
  end

  it "finds a session by id" do
    store.create(id: "test-1", role: "agent")
    row = store.find("test-1")
    expect(row).not_to be_nil
    expect(row[:role]).to eq("agent")
  end

  it "returns nil for unknown session" do
    expect(store.find("nonexistent")).to be_nil
  end

  it "seals a session" do
    store.create(id: "test-1", role: "agent")
    store.seal("test-1")
    expect(store.find("test-1")[:status]).to eq("sealed")
  end

  it "updates payload" do
    store.create(id: "test-1", role: "agent")
    store.update_payload("test-1", { loop_index: 3 })
    expect(store.find("test-1")[:payload]).to eq({ "loop_index" => 3 })
  end

  it "finds active session for role" do
    store.create(id: "test-1", role: "agent")
    row = store.active_for_role("agent")
    expect(row[:id]).to eq("test-1")
  end

  it "returns nil when no active session" do
    expect(store.active_for_role("nonexistent")).to be_nil
  end

  it "saves cursor_seq and contract_etag" do
    store.create(id: "test-1", role: "agent")
    store.save("test-1", cursor_seq: 42, contract_etag: "sha256:abc")
    row = store.find("test-1")
    expect(row[:cursor_seq]).to eq(42)
    expect(row[:contract_etag]).to eq("sha256:abc")
  end

  it "sweeps expired sessions" do
    store.create(id: "old", role: "agent", expires_at: Time.now.utc - 3600)
    store.create(id: "current", role: "agent")
    store.sweep_expired!
    expect(store.find("old")).to be_nil
    expect(store.find("current")).not_to be_nil
  end
end
