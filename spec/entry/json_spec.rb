require "spec_helper"
require "json"

RSpec.describe Textus::Entry::Json do
  describe ".parse" do
    it "extracts _meta into _meta and exposes data WITHOUT _meta as content" do
      raw = JSON.pretty_generate({ "_meta" => { "title" => "T" }, "name" => "x" })
      result = described_class.parse(raw, path: "x.json")
      expect(result["_meta"]).to eq({ "title" => "T" })
      expect(result["content"]).to eq({ "name" => "x" })
      expect(result["body"]).to eq(raw)
    end

    it "treats missing _meta as empty _meta" do
      raw = '{"name":"x"}'
      result = described_class.parse(raw, path: "x.json")
      expect(result["_meta"]).to eq({})
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
    it "round-trips content ↔ bytes (re-injects _meta on disk)" do
      content = { "data" => [1, 2] }
      meta    = { "k" => "v" }
      raw = described_class.serialize(meta: meta, body: "", content: content)
      parsed = described_class.parse(raw, path: "x.json")
      expect(parsed["_meta"]).to eq({ "k" => "v" })
      expect(parsed["content"]).to eq({ "data" => [1, 2] })
    end

    it "passes through body when content is absent" do
      raw = described_class.serialize(meta: {}, body: '{"a":1}', content: nil)
      expect(raw).to eq("{\"a\":1}\n")
    end

    it "raises UsageError if neither content nor body is given" do
      expect { described_class.serialize(meta: {}, body: "", content: nil) }
        .to raise_error(Textus::UsageError)
    end
  end

  describe ".extensions" do
    it { expect(described_class.extensions).to eq([".json"]) }
  end

  describe ".validate_against" do
    let(:schema) { instance_spy(Textus::Schema) }

    it "passes parsed content to schema.validate!" do
      described_class.validate_against(schema, { "_meta" => {}, "content" => { "x" => 1 } })
      expect(schema).to have_received(:validate!).with({ "x" => 1 })
    end

    it "passes empty hash when content is nil" do
      described_class.validate_against(schema, { "_meta" => {}, "content" => nil })
      expect(schema).to have_received(:validate!).with({})
    end
  end
end
