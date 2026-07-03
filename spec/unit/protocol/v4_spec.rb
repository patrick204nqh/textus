require "spec_helper"

RSpec.describe Textus::Protocol::V4 do
  describe "LANES" do
    it "declares exactly the 5 fixed lanes" do
      expect(described_class::LANES.keys).to contain_exactly(
        "knowledge", "scratchpad", "proposals", "artifacts", "raw"
      )
    end

    it "gives every lane a writers list and a description" do
      described_class::LANES.each_value do |row|
        expect(row[:writers]).to be_an(Array)
        expect(row[:desc]).to be_a(String)
      end
    end

    it "restricts artifacts to automation only" do
      expect(described_class::LANES["artifacts"][:writers]).to eq(%w[automation])
    end

    it "allows all three roles to write raw" do
      expect(described_class::LANES["raw"][:writers]).to contain_exactly("human", "agent", "automation")
    end
  end

  describe "NAMING_PATTERNS" do
    it "matches a sequential filename" do
      expect(described_class::NAMING_PATTERNS["sequential"]).to match("0001-topic-slug.md")
    end

    it "rejects a non-sequential filename" do
      expect(described_class::NAMING_PATTERNS["sequential"]).not_to match("topic-slug.md")
    end

    it "matches a dated filename" do
      expect(described_class::NAMING_PATTERNS["dated"]).to match("2026-07-02-slug.md")
    end
  end
end
