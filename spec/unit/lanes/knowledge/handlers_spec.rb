RSpec.describe Textus::Lanes::Knowledge::Handlers do
  describe ".loop" do
    it "returns nodes from manifest entries" do
      ctx = build_ctx
      manifest = double("Manifest", data: double("Data"))
      entries = [
        double("entry", key: "knowledge.loop.intent"),
        double("entry", key: "knowledge.loop.constraint"),
        double("entry", key: "knowledge.loop.judgment"),
      ]
      allow(manifest.data).to receive(:entries).and_return(entries)
      allow(ctx).to receive(:manifest).and_return(manifest)

      result = described_class.loop(ctx:, call: nil)
      expect(result["count"]).to eq(3)
      expect(result["loop"].map { |n| n["name"] }).to eq(%w[intent constraint judgment])
    end

    it "excludes non-loop and nested loop entries" do
      ctx = build_ctx
      manifest = double("Manifest", data: double("Data"))
      entries = [
        double("entry", key: "knowledge.loop.intent"),
        double("entry", key: "knowledge.identity"),
        double("entry", key: "knowledge.loop.constraint.repo"),
      ]
      allow(manifest.data).to receive(:entries).and_return(entries)
      allow(ctx).to receive(:manifest).and_return(manifest)

      result = described_class.loop(ctx:, call: nil)
      expect(result["count"]).to eq(1)
      expect(result["loop"].first["name"]).to eq("intent")
    end

    def build_ctx
      cursor_store = double("cursor_store", get_loop: { role: "agent", index: 0 })
      entry_index = double("entry_index", search: [])
      double("Textus::Protocol::Handlers::Context", cursor_store:, entry_index:)
    end
  end
end
