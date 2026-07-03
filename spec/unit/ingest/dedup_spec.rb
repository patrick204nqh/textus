RSpec.describe Textus::Ingest::Dedup do
  describe ".find" do
    it "returns key when content hash matches" do
      lookup = double("Index::Lookup")
      allow(lookup).to receive(:find_by_hash).with("sha256:abc").and_return("raw.2026.07.03.dup")
      allow(lookup).to receive(:find_by_url)

      result = described_class.find(lookup, "sha256:abc")
      expect(result).to eq("raw.2026.07.03.dup")
    end

    it "returns nil when no match" do
      lookup = double("Index::Lookup")
      allow(lookup).to receive(:find_by_hash).with("sha256:xyz").and_return(nil)

      result = described_class.find(lookup, "sha256:xyz")
      expect(result).to be_nil
    end

    it "falls back to URL lookup when hash misses and URL given" do
      lookup = double("Index::Lookup")
      allow(lookup).to receive(:find_by_hash).with("sha256:new").and_return(nil)
      allow(lookup).to receive(:find_by_url).with("https://example.com").and_return("raw.2026.06.01.old")

      result = described_class.find(lookup, "sha256:new", url: "https://example.com")
      expect(result).to eq("raw.2026.06.01.old")
    end
  end
end
