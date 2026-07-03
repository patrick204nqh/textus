RSpec.describe Textus::Lanes::Knowledge::Handlers do
  describe ".loop" do
    it "returns nodes from manifest entries" do
      ctx = instance_double("HandlerContext")
      manifest = instance_double("Manifest", data: double("data"))
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
      ctx = instance_double("HandlerContext")
      manifest = instance_double("Manifest", data: double("data"))
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
  end
end