RSpec.describe Textus::Infra::Store::CursorStore do
  subject(:store) { described_class.new(db) }

  let(:layout) { Textus::Protocol::Layout.new(Dir.mktmpdir("textus-test-")) }
  let(:db) { Textus::Infra::Database.new(layout:).setup!.connection }

  describe "#read / #write" do
    it "defaults to 0" do
      expect(store.read("agent")).to eq(0)
    end

    it "persists and reads back" do
      store.write("agent", 42)
      expect(store.read("agent")).to eq(42)
    end

    it "updates in place" do
      store.write("agent", 1)
      store.write("agent", 99)
      expect(store.read("agent")).to eq(99)
    end

    it "isolates by role" do
      store.write("agent", 10)
      store.write("human", 20)
      expect(store.read("agent")).to eq(10)
      expect(store.read("human")).to eq(20)
    end
  end

  describe "#read_loop_position / #write_loop_position" do
    it "defaults to 0" do
      expect(store.read_loop_position("agent")).to eq(0)
    end

    it "persists and reads back" do
      store.write_loop_position("agent", 3)
      expect(store.read_loop_position("agent")).to eq(3)
    end

    it "updates in place" do
      store.write_loop_position("agent", 1)
      store.write_loop_position("agent", 7)
      expect(store.read_loop_position("agent")).to eq(7)
    end

    it "isolates by role" do
      store.write_loop_position("agent", 2)
      store.write_loop_position("human", 5)
      expect(store.read_loop_position("agent")).to eq(2)
      expect(store.read_loop_position("human")).to eq(5)
    end

    it "does not interfere with cursor positions" do
      store.write("agent", 100)
      store.write_loop_position("agent", 5)
      expect(store.read("agent")).to eq(100)
      expect(store.read_loop_position("agent")).to eq(5)
    end
  end
end
