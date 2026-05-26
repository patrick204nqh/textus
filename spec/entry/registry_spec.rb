require "spec_helper"

RSpec.describe Textus::Entry do
  describe ".infer_from_extension" do
    it "maps .md to markdown" do
      expect(described_class.infer_from_extension(".md")).to eq("markdown")
    end

    it "maps .json to json" do
      expect(described_class.infer_from_extension(".json")).to eq("json")
    end

    it "maps .yaml and .yml to yaml" do
      expect(described_class.infer_from_extension(".yaml")).to eq("yaml")
      expect(described_class.infer_from_extension(".yml")).to eq("yaml")
    end

    it "maps .txt to text" do
      expect(described_class.infer_from_extension(".txt")).to eq("text")
    end

    it "returns nil for unknown extensions" do
      expect(described_class.infer_from_extension(".xyz")).to be_nil
      expect(described_class.infer_from_extension("")).to be_nil
    end
  end

  describe ".formats" do
    it "returns the four known format names" do
      expect(described_class.formats).to contain_exactly("markdown", "json", "yaml", "text")
    end
  end
end
