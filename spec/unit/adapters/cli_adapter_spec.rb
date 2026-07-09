RSpec.describe Textus::Adapters::CliAdapter do
  subject(:adapter) { described_class.new }

  describe "#normalize" do
    it "extracts verb from first non-flag argument" do
      req = adapter.normalize(%w[get --key=test])
      expect(req.verb).to eq(:get)
    end

    it "extracts --as= role" do
      req = adapter.normalize(%w[put --key=test --as=human])
      expect(req.role).to eq("human")
    end

    it "defaults role when --as= absent" do
      req = adapter.normalize(%w[get])
      expect(req.role).to eq("human")
    end

    it "captures positional args as params" do
      req = adapter.normalize(%w[get knowledge.intent.0001-north-star])
      expect(req.params).to include(:key)
    end
  end
end
