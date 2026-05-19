require "spec_helper"

RSpec.describe Textus::Entry::Text do
  describe ".parse" do
    it "returns empty frontmatter and the raw body" do
      result = described_class.parse("hello world\n", path: "x.txt")
      expect(result["frontmatter"]).to eq({})
      expect(result["body"]).to eq("hello world\n")
      expect(result["content"]).to be_nil
    end

    it "raises on invalid UTF-8" do
      raw = "bad\xC3\x28".dup.force_encoding(Encoding::UTF_8)
      expect { described_class.parse(raw, path: "x.txt") }
        .to raise_error(Textus::BadFrontmatter)
    end
  end

  describe ".serialize" do
    it "round-trips bytes and ignores frontmatter/content" do
      raw = described_class.serialize(frontmatter: { "ignored" => true }, body: "abc", content: { "x" => 1 })
      expect(raw).to eq("abc\n")
      parsed = described_class.parse(raw, path: "x.txt")
      expect(parsed["body"]).to eq("abc\n")
    end

    it "preserves existing trailing newline without doubling" do
      raw = described_class.serialize(frontmatter: {}, body: "abc\n", content: nil)
      expect(raw).to eq("abc\n")
    end
  end

  describe ".extensions" do
    it { expect(described_class.extensions).to eq([".txt"]) }
  end
end
