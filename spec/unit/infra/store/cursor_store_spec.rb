RSpec.describe Textus::Infra::Store::CursorStore do
  subject(:store) { described_class.new(db) }

  let(:layout) { Textus::Protocol::Layout.new(Dir.mktmpdir("textus-test-")) }
  let(:db) { Textus::Infra::Database.new(layout:).setup!.connection }

  describe "#get / #set" do
    it "defaults to seq 0" do
      expect(store.get("agent")).to eq({ role: "agent", seq: 0 })
    end

    it "persists and reads back" do
      store.set("agent", 42)
      expect(store.get("agent")).to include(role: "agent", seq: 42)
    end

    it "updates in place" do
      store.set("agent", 1)
      store.set("agent", 99)
      expect(store.get("agent")).to include(role: "agent", seq: 99)
    end

    it "isolates by role" do
      store.set("agent", 10)
      store.set("human", 20)
      expect(store.get("agent")).to include(role: "agent", seq: 10)
      expect(store.get("human")).to include(role: "human", seq: 20)
    end
  end

  describe "#get_loop / #set_loop" do
    it "defaults to index 0" do
      expect(store.get_loop("agent")).to eq({ role: "agent", index: 0 })
    end

    it "persists and reads back" do
      store.set_loop("agent", 3)
      expect(store.get_loop("agent")).to include(role: "agent", index: 3)
    end

    it "updates in place" do
      store.set_loop("agent", 1)
      store.set_loop("agent", 7)
      expect(store.get_loop("agent")).to include(role: "agent", index: 7)
    end

    it "isolates by role" do
      store.set_loop("agent", 2)
      store.set_loop("human", 5)
      expect(store.get_loop("agent")).to include(role: "agent", index: 2)
      expect(store.get_loop("human")).to include(role: "human", index: 5)
    end

    it "does not interfere with cursor positions" do
      store.set("agent", 100)
      store.set_loop("agent", 5)
      expect(store.get("agent")).to include(role: "agent", seq: 100)
      expect(store.get_loop("agent")).to include(role: "agent", index: 5)
    end
  end
end
