RSpec.describe Textus::Ingest::KeyBuilder do
  describe ".derive_key" do
    it "formats key from date, kind, slug" do
      now = Time.new(2026, 7, 3, 12, 0, 0, "UTC")
      result = described_class.derive_key(now, "url", "my-link")
      expect(result).to eq("raw.2026.07.03.url-my-link")
    end

    it "includes kind in key" do
      now = Time.new(2026, 7, 3, 12, 0, 0, "UTC")
      url_key = described_class.derive_key(now, "url", "test")
      asset_key = described_class.derive_key(now, "asset", "test")
      expect(url_key).to include("url-")
      expect(asset_key).to include("asset-")
    end
  end

  describe ".compute_hash" do
    it "hashes url content" do
      result = described_class.compute_hash(kind: "url", url: "https://example.com")
      expect(result).to match(/\Asha256:[a-f0-9]{64}\z/)
    end

    it "hashes file content" do
      Tempfile.create do |f|
        f.write("hello")
        f.rewind
        result = described_class.compute_hash(kind: "file", path: f.path)
        expect(result).to match(/\Asha256:[a-f0-9]{64}\z/)
      end
    end

    it "raises on unknown kind" do
      expect do
        described_class.compute_hash(kind: "unknown")
      end.to raise_error(ArgumentError, /unknown kind/)
    end
  end
end
