require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Parser do
  describe ".call" do
    it "builds a Leaf entry for a key with no existing directory" do
      entry = described_class.call({ "key" => "knowledge.identity", "lane" => "knowledge" }, root: "/nonexistent")
      expect(entry).to be_a(Textus::Manifest::Entry::Leaf)
    end

    it "builds a Produced entry for a new key in the artifacts lane" do
      entry = described_class.call({ "key" => "artifacts.boot", "lane" => "artifacts" }, root: "/nonexistent")
      expect(entry).to be_a(Textus::Manifest::Entry::Produced)
    end

    it "accepts naming: and rejects an unknown alias" do
      entry = described_class.call({ "key" => "knowledge.judgment", "lane" => "knowledge", "naming" => "sequential" }, root: "/nonexistent")
      expect(entry.naming).to eq("sequential")

      expect do
        described_class.call({ "key" => "knowledge.x", "lane" => "knowledge", "naming" => "bogus" }, root: "/nonexistent")
      end.to raise_error(Textus::BadManifest, /unknown naming alias/)
    end

    it "no longer exposes owner as a reader" do
      entry = described_class.call({ "key" => "knowledge.x", "lane" => "knowledge" }, root: "/nonexistent")
      expect(entry).not_to respond_to(:owner)
    end
  end
end
