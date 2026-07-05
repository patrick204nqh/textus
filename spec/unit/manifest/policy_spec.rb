RSpec.describe Textus::Protocol::Manifest::Policy do
  let(:data) { instance_double("Textus::Protocol::Manifest::Data") }
  subject(:policy) { described_class.new(data) }

  describe "#allowed?" do
    it "allows a writer in V4::LANES for the lane" do
      result = policy.allowed?(role: :human, lane: "knowledge")
      expect(result).to be true
    end

    it "denies a non-writer for the lane" do
      result = policy.allowed?(role: :automation, lane: "knowledge")
      expect(result).to be false
    end

    it "allows the automation role in artifacts lane" do
      result = policy.allowed?(role: :automation, lane: "artifacts")
      expect(result).to be true
    end

    it "allows all roles in raw lane" do
      %i[human agent automation].each do |role|
        expect(policy.allowed?(role:, lane: "raw")).to be true
      end
    end

    it "returns false for an unknown lane" do
      result = policy.allowed?(role: :human, lane: "nonexistent")
      expect(result).to be false
    end
  end

  describe "#allowed!" do
    it "does not raise for an allowed role" do
      expect { policy.allowed!(role: :human, lane: "knowledge") }.not_to raise_error
    end

    it "raises WriteForbidden for a disallowed role" do
      expect { policy.allowed!(role: :automation, lane: "knowledge") }
        .to raise_error(Textus::WriteForbidden)
    end
  end

  describe "#writers_for" do
    it "returns writers for a known lane" do
      expect(policy.writers_for("knowledge")).to eq(%w[human])
    end

    it "returns empty array for unknown lane" do
      expect(policy.writers_for("unknown")).to eq([])
    end
  end

  describe "#actor_for" do
    it "returns the first writer for the lane" do
      expect(policy.actor_for("knowledge")).to eq("human")
    end
  end
end
