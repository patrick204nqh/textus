RSpec.describe Textus::Protocol::SessionStore do
  let(:db) do
    Sequel.sqlite(":memory:").tap do |d|
      d.create_table(:sessions) do
        String :id, primary_key: true
        String :role, null: false
        String :surface_id
        Integer :cursor_seq
        String :contract_etag
        DateTime :expires_at
        DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      end
    end
  end
  subject(:store) { described_class.new(db) }

  describe "#create" do
    it "inserts and returns the session" do
      session = store.create(id: "2026-01-01-abc", role: "agent")
      expect(session[:id]).to eq("2026-01-01-abc")
      expect(session[:role]).to eq("agent")
    end
  end

  describe "#find" do
    it "finds an existing session" do
      store.create(id: "s1", role: "human")
      found = store.find("s1")
      expect(found[:id]).to eq("s1")
      expect(found[:role]).to eq("human")
    end

    it "returns nil for missing session" do
      expect(store.find("nonexistent")).to be_nil
    end
  end

  describe "#save" do
    it "updates cursor_seq and contract_etag" do
      store.create(id: "s1", role: "agent")
      store.save("s1", cursor_seq: 42, contract_etag: "abc")
      updated = store.find("s1")
      expect(updated[:cursor_seq]).to eq(42)
      expect(updated[:contract_etag]).to eq("abc")
    end

    it "does nothing when no updates given" do
      store.create(id: "s1", role: "agent")
      expect { store.save("s1") }.not_to raise_error
    end
  end

  describe "#sweep_expired!" do
    it "deletes expired sessions" do
      store.create(id: "expired", role: "agent", expires_at: Time.now.utc - 3600)
      store.create(id: "active", role: "agent", expires_at: Time.now.utc + 3600)
      count = store.sweep_expired!
      expect(count).to eq(1)
      expect(store.find("expired")).to be_nil
      expect(store.find("active")).not_to be_nil
    end
  end
end
