require "spec_helper"

RSpec.describe Textus::Key::Matching do
  describe ".matches_prefix?" do
    it "matches an exact key" do
      expect(described_class.matches_prefix?("artifacts", "artifacts")).to be(true)
    end

    it "matches a dotted descendant" do
      expect(described_class.matches_prefix?("artifacts.orientation", "artifacts")).to be(true)
    end

    it "does NOT match a partial-segment prefix (dotted boundary)" do
      # the divergence WS4 fixed: materialize used a loose start_with? here
      expect(described_class.matches_prefix?("artifacts", "art")).to be(false)
    end

    it "does not match a sibling key" do
      expect(described_class.matches_prefix?("knowledge.agents", "artifacts")).to be(false)
    end

    describe "the Nested ancestor case" do
      it "selects a nested entry when the prefix descends INTO it" do
        expect(described_class.matches_prefix?("feeds.machines", "feeds.machines.host1", nested: true)).to be(true)
      end

      it "is off by default (a leaf entry is not selected by a deeper prefix)" do
        expect(described_class.matches_prefix?("feeds.machines", "feeds.machines.host1")).to be(false)
      end

      it "still requires the dotted boundary even for nested entries" do
        expect(described_class.matches_prefix?("feeds.machines", "feeds.mac", nested: true)).to be(false)
      end
    end
  end
end
