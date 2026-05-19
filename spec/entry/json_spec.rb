require "spec_helper"
require "json"

RSpec.describe Textus::Entry::Json do
  describe ".parse" do
    it "extracts _meta into frontmatter and exposes full hash as content" do
      raw = JSON.pretty_generate({ "_meta" => { "title" => "T" }, "name" => "x" })
      result = described_class.parse(raw, path: "x.json")
      expect(result["frontmatter"]).to eq({ "title" => "T" })
      expect(result["content"]).to eq({ "_meta" => { "title" => "T" }, "name" => "x" })
      expect(result["body"]).to eq(raw)
    end

    it "treats missing _meta as empty frontmatter" do
      raw = '{"name":"x"}'
      result = described_class.parse(raw, path: "x.json")
      expect(result["frontmatter"]).to eq({})
      expect(result["content"]).to eq({ "name" => "x" })
    end

    it "raises BadFrontmatter on invalid JSON" do
      expect { described_class.parse("not json", path: "x.json") }
        .to raise_error(Textus::BadFrontmatter, /JSON parse failed/)
    end

    it "rejects non-object top level" do
      expect { described_class.parse("[1,2,3]", path: "x.json") }
        .to raise_error(Textus::BadFrontmatter, /top-level must be an object/)
    end
  end

  describe ".serialize" do
    it "round-trips content ↔ bytes" do
      content = { "_meta" => { "k" => "v" }, "data" => [1, 2] }
      raw = described_class.serialize(frontmatter: {}, body: "", content: content)
      parsed = described_class.parse(raw, path: "x.json")
      expect(parsed["content"]).to eq(content)
      expect(parsed["frontmatter"]).to eq({ "k" => "v" })
    end

    it "passes through body when content is absent" do
      raw = described_class.serialize(frontmatter: {}, body: '{"a":1}', content: nil)
      expect(raw).to eq("{\"a\":1}\n")
    end

    it "raises UsageError if neither content nor body is given" do
      expect { described_class.serialize(frontmatter: {}, body: "", content: nil) }
        .to raise_error(Textus::UsageError)
    end
  end

  describe ".extensions" do
    it { expect(described_class.extensions).to eq([".json"]) }
  end
end
