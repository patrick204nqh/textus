require "spec_helper"

RSpec.describe Textus::Entry::Yaml do
  describe ".parse" do
    it "extracts _meta into frontmatter and exposes full hash as content" do
      raw = "_meta:\n  title: T\nname: x\n"
      result = described_class.parse(raw, path: "x.yaml")
      expect(result["frontmatter"]).to eq({ "title" => "T" })
      expect(result["content"]).to eq({ "_meta" => { "title" => "T" }, "name" => "x" })
      expect(result["body"]).to eq(raw)
    end

    it "treats missing _meta as empty frontmatter" do
      result = described_class.parse("name: x\n", path: "x.yaml")
      expect(result["frontmatter"]).to eq({})
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
    it "round-trips content ↔ bytes" do
      content = { "_meta" => { "k" => "v" }, "data" => [1, 2] }
      raw = described_class.serialize(frontmatter: {}, body: "", content: content)
      expect(raw).not_to start_with("---\n")
      parsed = described_class.parse(raw, path: "x.yaml")
      expect(parsed["content"]).to eq(content)
      expect(parsed["frontmatter"]).to eq({ "k" => "v" })
    end

    it "passes through body when content is absent" do
      raw = described_class.serialize(frontmatter: {}, body: "a: 1", content: nil)
      expect(raw).to eq("a: 1\n")
    end

    it "raises UsageError if neither content nor body is given" do
      expect { described_class.serialize(frontmatter: {}, body: "", content: nil) }
        .to raise_error(Textus::UsageError)
    end
  end

  describe ".extensions" do
    it { expect(described_class.extensions).to eq([".yaml", ".yml"]) }
  end
end
