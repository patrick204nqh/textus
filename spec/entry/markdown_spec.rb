require "spec_helper"

RSpec.describe Textus::Entry::Markdown do
  describe ".parse" do
    it "parses frontmatter and body" do
      raw = "---\ntitle: Hello\ntags:\n  - a\n---\nBody here\n"
      result = described_class.parse(raw, path: "x.md")
      expect(result["frontmatter"]).to eq({ "title" => "Hello", "tags" => ["a"] })
      expect(result["body"]).to eq("Body here\n")
      expect(result["content"]).to be_nil
    end

    it "handles body-only files" do
      result = described_class.parse("plain body\n", path: "x.md")
      expect(result["frontmatter"]).to eq({})
      expect(result["body"]).to eq("plain body\n")
      expect(result["content"]).to be_nil
    end

    it "handles empty frontmatter" do
      result = described_class.parse("---\n---\nbody\n", path: "x.md")
      expect(result["frontmatter"]).to eq({})
      expect(result["body"]).to eq("body\n")
    end

    it "raises BadFrontmatter when fence is unterminated" do
      expect do
        described_class.parse("---\ntitle: x\nbody never ends", path: "x.md")
      end.to raise_error(Textus::BadFrontmatter)
    end
  end

  describe ".serialize" do
    it "round-trips frontmatter + body" do
      raw = described_class.serialize(frontmatter: { "title" => "Hi" }, body: "hello")
      parsed = described_class.parse(raw)
      expect(parsed["frontmatter"]).to eq({ "title" => "Hi" })
      expect(parsed["body"]).to eq("hello\n")
    end

    it "emits empty frontmatter block when frontmatter is empty" do
      raw = described_class.serialize(frontmatter: {}, body: "b")
      expect(raw).to start_with("---\n---\n")
    end
  end

  describe ".extensions" do
    it "returns .md" do
      expect(described_class.extensions).to eq([".md"])
    end
  end
end
