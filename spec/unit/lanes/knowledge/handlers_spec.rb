RSpec.describe Textus::Lanes::Knowledge::Handlers do
  describe ".loop" do
    let(:manifest) do
      entries = [
        entry("knowledge.loop.intent"),
        entry("knowledge.loop.constraint"),
        entry("knowledge.loop.judgment"),
        entry("knowledge.loop.evidence"),
        entry("knowledge.loop.execution"),
        entry("knowledge.loop.adoption"),
        entry("knowledge.boot"), # non-loop entry
      ]
      d = double("ManifestData", entries:)
      double("Manifest", data: d)
    end

    def entry(key)
      instance_double(Textus::Protocol::Manifest::Entry::Base, key:)
    end

    it "returns loop nodes derived from manifest" do
      ctx = double("QueryContext", manifest:, entry_index: double("entry_index", search: []))
      result = described_class.loop(ctx:, call: nil)
      expect(result["count"]).to eq(6)
      expect(result["loop"].map { |n| n["name"] }).to eq(%w[
                                                           intent constraint judgment
                                                           evidence execution adoption
                                                         ])
    end

    it "maps each node to its manifest entry key" do
      ctx = double("QueryContext", manifest:, entry_index: double("entry_index", search: []))
      result = described_class.loop(ctx:, call: nil)
      expect(result["loop"].map { |n| n["key"] }).to eq([
                                                          "knowledge.loop.intent",
                                                          "knowledge.loop.constraint",
                                                          "knowledge.loop.judgment",
                                                          "knowledge.loop.evidence",
                                                          "knowledge.loop.execution",
                                                          "knowledge.loop.adoption",
                                                        ])
    end
  end
end
