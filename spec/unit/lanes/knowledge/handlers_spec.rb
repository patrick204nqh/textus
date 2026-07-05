RSpec.describe Textus::Lanes::Knowledge::Handlers do
  describe ".loop" do
    let(:manifest) do
      d = double("ManifestData")
      double("Manifest", data: d).tap { |_m| allow(d).to receive(:entries).and_return([]) }
    end

    it "returns the 8 canonical loop nodes" do
      ctx = build_ctx(manifest)
      result = described_class.loop(ctx:, call: nil)
      expect(result["count"]).to eq(8)
      expect(result["loop"].map { |n| n["name"] }).to eq(%w[
                                                           intent constraint.repo constraint.protocol
                                                           judgment.engineering judgment.agent-behavior
                                                           evidence execution feedback
                                                         ])
    end

    it "maps each node to its manifest entry key" do
      ctx = build_ctx(manifest)
      result = described_class.loop(ctx:, call: nil)
      expect(result["loop"].map { |n| n["key"] }).to eq([
                                                          "knowledge.loop.intent",
                                                          "knowledge.loop.constraint.repo",
                                                          "knowledge.loop.constraint.protocol",
                                                          "knowledge.loop.judgment.engineering",
                                                          "knowledge.loop.judgment.agent-behavior",
                                                          "knowledge.loop.evidence",
                                                          "knowledge.loop.execution.runbook",
                                                          "knowledge.loop.feedback",
                                                        ])
    end

    def build_ctx(manifest = nil)
      cursor_store = double("cursor_store", get_loop: { role: "agent", index: 0 })
      entry_index = double("entry_index", search: [])
      if manifest
        double("Textus::Protocol::Handlers::QueryContext", cursor_store:, entry_index:, manifest:)
      else
        double("Textus::Protocol::Handlers::QueryContext", cursor_store:, entry_index:)
      end
    end
  end
end
