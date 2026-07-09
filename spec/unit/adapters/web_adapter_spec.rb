RSpec.describe Textus::Adapters::WebAdapter do
  subject(:adapter) { described_class.new }

  describe "#normalize" do
    it "extracts verb and removes it from params" do
      req = adapter.normalize({ "verb" => "get", "key" => "test" })
      expect(req.verb).to eq(:get)
      expect(req.params).to eq({ key: "test" })
    end

    it "symbolizes remaining params" do
      req = adapter.normalize({ "verb" => "list", "under" => "knowledge" })
      expect(req.params).to eq({ under: "knowledge" })
    end

    it "passes role and session_id through" do
      req = adapter.normalize({
        "verb" => "put", "key" => "x", "role" => "human", "session_id" => "s-1"
      })
      expect(req.role).to eq("human")
      expect(req.session_id).to eq("s-1")
    end
  end
end
