RSpec.describe Textus::Adapters::McpAdapter do
  subject(:adapter) { described_class.new }

  describe "#normalize" do
    it "extracts verb from method field" do
      req = adapter.normalize({ "method" => "get" })
      expect(req.verb).to eq(:get)
    end

    it "symbolizes params keys" do
      req = adapter.normalize({ "method" => "get", "params" => { "key" => "test" } })
      expect(req.params).to eq({ key: "test" })
    end

    it "defaults params to empty hash" do
      req = adapter.normalize({ "method" => "get" })
      expect(req.params).to eq({})
    end

    it "passes role and session_id through" do
      req = adapter.normalize({
        "method" => "propose", "role" => "agent", "session_id" => "s-123"
      })
      expect(req.role).to eq("agent")
      expect(req.session_id).to eq("s-123")
    end
  end
end
