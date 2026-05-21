require "spec_helper"

RSpec.describe Textus::Entry::Yaml do
  describe ".parse" do
    it "extracts _meta into _meta and exposes data WITHOUT _meta as content" do
      raw = "_meta:\n  title: T\nname: x\n"
      result = described_class.parse(raw, path: "x.yaml")
      expect(result["_meta"]).to eq({ "title" => "T" })
      expect(result["content"]).to eq({ "name" => "x" })
      expect(result["body"]).to eq(raw)
    end

    it "treats missing _meta as empty _meta" do
      result = described_class.parse("name: x\n", path: "x.yaml")
      expect(result["_meta"]).to eq({})
      expect(result["content"]).to eq({ "name" => "x" })
    end

    it "rejects anchors/aliases" do
      raw = "base: &a\n  k: v\nchild: *a\n"
      expect { described_class.parse(raw, path: "x.yaml") }
        .to raise_error(Textus::BadFrontmatter)
    end

    it "rejects non-mapping top level" do
      expect { described_class.parse("- 1\n- 2\n", path: "x.yaml") }
        .to raise_error(Textus::BadFrontmatter, /top-level must be a mapping/)
    end

    it "preserves quoted strings (Norway-problem mitigation)" do
      # Psych in current Ruby still follows YAML 1.1 booleans (NO → false),
      # so authors must quote ambiguous scalars. This regression locks in
      # the safe path: when quoted, "NO" stays "NO".
      result = described_class.parse(%(country: "NO"\n), path: "x.yaml")
      expect(result["content"]).to eq({ "country" => "NO" })
    end
  end

  describe ".serialize" do
    it "round-trips content ↔ bytes (re-injects _meta on disk)" do
      content = { "data" => [1, 2] }
      meta    = { "k" => "v" }
      raw = described_class.serialize(meta: meta, body: "", content: content)
      expect(raw).not_to start_with("---\n")
      parsed = described_class.parse(raw, path: "x.yaml")
      expect(parsed["_meta"]).to eq({ "k" => "v" })
      expect(parsed["content"]).to eq({ "data" => [1, 2] })
    end

    it "passes through body when content is absent" do
      raw = described_class.serialize(meta: {}, body: "a: 1", content: nil)
      expect(raw).to eq("a: 1\n")
    end

    it "raises UsageError if neither content nor body is given" do
      expect { described_class.serialize(meta: {}, body: "", content: nil) }
        .to raise_error(Textus::UsageError)
    end
  end

  describe ".extensions" do
    it { expect(described_class.extensions).to eq([".yaml", ".yml"]) }
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
