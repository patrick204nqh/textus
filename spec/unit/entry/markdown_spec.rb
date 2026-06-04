require "spec_helper"

RSpec.describe Textus::Entry::Markdown do
  describe ".parse" do
    it "parses frontmatter and body" do
      raw = "---\ntitle: Hello\ntags:\n  - a\n---\nBody here\n"
      result = described_class.parse(raw, path: "x.md")
      expect(result["_meta"]).to eq({ "title" => "Hello", "tags" => ["a"] })
      expect(result["body"]).to eq("Body here\n")
      expect(result["content"]).to be_nil
    end

    it "handles body-only files" do
      result = described_class.parse("plain body\n", path: "x.md")
      expect(result["_meta"]).to eq({})
      expect(result["body"]).to eq("plain body\n")
      expect(result["content"]).to be_nil
    end

    it "handles empty frontmatter" do
      result = described_class.parse("---\n---\nbody\n", path: "x.md")
      expect(result["_meta"]).to eq({})
      expect(result["body"]).to eq("body\n")
    end

    it "raises BadFrontmatter when fence is unterminated" do
      expect do
        described_class.parse("---\ntitle: x\nbody never ends", path: "x.md")
      end.to raise_error(Textus::BadFrontmatter)
    end
  end

  describe ".serialize" do
    it "round-trips _meta + body" do
      raw = described_class.serialize(meta: { "title" => "Hi" }, body: "hello")
      parsed = described_class.parse(raw)
      expect(parsed["_meta"]).to eq({ "title" => "Hi" })
      expect(parsed["body"]).to eq("hello\n")
    end

    it "emits empty frontmatter block when meta is empty" do
      raw = described_class.serialize(meta: {}, body: "b")
      expect(raw).to start_with("---\n---\n")
    end
  end

  describe ".extensions" do
    it "returns .md" do
      expect(described_class.extensions).to eq([".md"])
    end
  end

  describe ".validate_against" do
    let(:schema) { instance_spy(Textus::Schema) }

    it "passes parsed _meta to schema.validate!" do
      described_class.validate_against(schema, { "_meta" => { "name" => "x" }, "body" => "" })
      expect(schema).to have_received(:validate!).with({ "name" => "x" })
    end
  end
end
