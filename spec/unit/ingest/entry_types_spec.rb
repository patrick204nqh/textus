RSpec.describe Textus::Ingest::EntryTypes do
  describe ".for" do
    it "returns Link module for link kind" do
      expect(described_class.for("link")).to eq(Textus::Ingest::EntryTypes::Link)
    end

    it "returns Asset module for asset kind" do
      expect(described_class.for("asset")).to eq(Textus::Ingest::EntryTypes::Asset)
    end

    it "returns Text module for text kind" do
      expect(described_class.for("text")).to eq(Textus::Ingest::EntryTypes::Text)
    end

    it "raises for unknown kind" do
      expect { described_class.for("invalid") }.to raise_error(ArgumentError, /unknown ingest kind/)
    end
  end

  describe Textus::Ingest::EntryTypes::Link do
    describe ".build" do
      it "returns url source hash" do
        result = described_class.build(url: "https://example.com", label: "Example")
        expect(result).to eq({
                               "source" => { "kind" => "url", "url" => "https://example.com", "label" => "Example" },
                               "body" => nil,
                             })
      end

      it "uses url as default label" do
        result = described_class.build(url: "https://example.com")
        expect(result["source"]["label"]).to eq("https://example.com")
      end
    end
  end

  describe Textus::Ingest::EntryTypes::Asset do
    describe ".build" do
      it "copies file and returns asset reference" do
        layout = instance_double("Layout")
        time = Time.new(2026, 7, 3, 12, 0, 0, "UTC")
        expect(layout).to receive(:asset_raw_dir).with("2026/07/03", "screenshots").and_return("/tmp/assets/raw/2026/07/03/screenshots")
        expect(layout).to receive(:asset_sentinel_path).and_return("/tmp/assets/.gitignore")
        expect(FileUtils).to receive(:mkdir_p).with("/tmp/assets/raw/2026/07/03/screenshots")
        expect(FileUtils).to receive(:cp).with("/tmp/photo.png", "/tmp/assets/raw/2026/07/03/screenshots/photo.png")
        allow(File).to receive(:exist?).with("/tmp/assets/.gitignore").and_return(true)

        result = described_class.build(
          path: "/tmp/photo.png", lane: "screenshots",
          time:, layout:, label: "Photo"
        )
        expect(result["source"]["kind"]).to eq("asset")
        expect(result["source"]["label"]).to eq("Photo")
        expect(result["asset"]).to eq("raw/2026/07/03/screenshots/photo.png")
        expect(result["body"]).to be_nil
      end
    end

    describe ".copy" do
      it "copies file to asset dir" do
        layout = instance_double("Layout")
        time = Time.new(2026, 7, 3, 12, 0, 0, "UTC")
        expect(layout).to receive(:asset_raw_dir).with("2026/07/03", "diagrams").and_return("/tmp/assets/raw/2026/07/03/diagrams")
        expect(layout).to receive(:asset_sentinel_path).and_return("/tmp/assets/.gitignore")
        expect(FileUtils).to receive(:mkdir_p).with("/tmp/assets/raw/2026/07/03/diagrams")
        expect(FileUtils).to receive(:cp).with("/tmp/diagram.png", "/tmp/assets/raw/2026/07/03/diagrams/diagram.png")
        allow(File).to receive(:exist?).with("/tmp/assets/.gitignore").and_return(true)

        result = described_class.copy("/tmp/diagram.png", lane: "diagrams", time:, layout:)
        expect(result).to eq("raw/2026/07/03/diagrams/diagram.png")
      end
    end

    describe ".move" do
      it "moves asset to new date path" do
        layout = instance_double("Layout")
        expect(layout).to receive(:asset_resolve).with("raw/2026/06/01/diagrams/old.png").and_return("/tmp/assets/raw/2026/06/01/diagrams/old.png")
        expect(File).to receive(:exist?).with("/tmp/assets/raw/2026/06/01/diagrams/old.png").and_return(true)
        expect(layout).to receive(:asset_raw_dir).with(%r{2026/07/03}, "diagrams").and_return("/tmp/assets/raw/2026/07/03/diagrams")
        expect(FileUtils).to receive(:mkdir_p).with("/tmp/assets/raw/2026/07/03/diagrams")
        expect(FileUtils).to receive(:mv).with("/tmp/assets/raw/2026/06/01/diagrams/old.png", "/tmp/assets/raw/2026/07/03/diagrams/old.png")

        allow(Time).to receive(:now).and_return(Time.new(2026, 7, 3, 12, 0, 0, "UTC"))
        described_class.move("raw/2026/06/01/diagrams/old.png", "diagrams", layout)
      end

      it "does nothing if source missing" do
        layout = instance_double("Layout")
        expect(layout).to receive(:asset_resolve).and_return("/tmp/assets/missing.png")
        expect(File).to receive(:exist?).and_return(false)
        expect(FileUtils).not_to receive(:mv)

        described_class.move("raw/missing.png", "diagrams", layout)
      end
    end
  end

  describe Textus::Ingest::EntryTypes::Text do
    describe ".build" do
      it "reads file and returns body" do
        Tempfile.create do |f|
          f.write("article content")
          f.rewind
          result = described_class.build(path: f.path, label: "Article")
          expect(result["source"]).to eq({ "kind" => "file", "path" => f.path, "label" => "Article" })
          expect(result["body"]).to eq("article content")
        end
      end

      it "uses basename as default label" do
        Tempfile.create(["test", ".md"]) do |f|
          f.write("content")
          f.rewind
          result = described_class.build(path: f.path)
          expect(result["source"]["label"]).to eq(File.basename(f.path))
        end
      end
    end
  end
end
