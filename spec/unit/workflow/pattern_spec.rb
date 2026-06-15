RSpec.describe Textus::Workflow::Pattern do
  describe ".match?" do
    it "exact match" do
      expect(described_class.match?("knowledge.notes.x", "knowledge.notes.x")).to be true
      expect(described_class.match?("knowledge.notes.x", "knowledge.notes.y")).to be false
    end

    it "single-level glob (*)" do
      expect(described_class.match?("artifacts.feeds.github.*", "artifacts.feeds.github.repos")).to be true
      expect(described_class.match?("artifacts.feeds.github.*", "artifacts.feeds.github.repos.sub")).to be false
      expect(described_class.match?("artifacts.feeds.github.*", "artifacts.feeds.github")).to be false
    end

    it "deep glob (**)" do
      expect(described_class.match?("artifacts.feeds.**", "artifacts.feeds.github.repos")).to be true
      expect(described_class.match?("artifacts.feeds.**", "artifacts.feeds.github.repos.sub")).to be true
      expect(described_class.match?("artifacts.feeds.**", "artifacts.other.x")).to be false
    end
  end
end
