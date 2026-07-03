require "spec_helper"

RSpec.describe Textus::Domain::Lane do
  describe ".writers_for" do
    it "returns the fixed writers list for a known lane" do
      expect(described_class.writers_for("knowledge")).to eq(%w[human])
    end

    it "returns an empty list for an unknown lane" do
      expect(described_class.writers_for("nonexistent")).to eq([])
    end
  end

  describe ".proposer_role" do
    it "returns a role that can write proposals but isn't the sole knowledge writer" do
      expect(described_class.proposer_role).to eq("agent")
    end
  end

  describe ".propose_lane_for" do
    it "returns 'proposals' for a role that can write it" do
      expect(described_class.propose_lane_for("agent")).to eq("proposals")
    end

    it "returns nil for a role that can't write proposals" do
      expect(described_class.propose_lane_for("automation")).to be_nil
    end
  end
end
