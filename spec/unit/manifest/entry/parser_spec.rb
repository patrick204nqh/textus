require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Parser do
  describe ".call" do
    it "extracts the required fields" do
      entry = described_class.call(
        { "key" => "working.foo", "path" => "foo.md", "lane" => "working", "kind" => "leaf" },
      )
      expect(entry.key).to eq("working.foo")
      expect(entry.path).to eq("foo.md")
      expect(entry.lane).to eq("working")
      expect(entry).to be_a(Textus::Manifest::Entry::Leaf)
      expect(entry.format).to eq("markdown")
    end

    it "raises when key is missing" do
      expect { described_class.call({ "path" => "foo.md", "lane" => "working" }) }
        .to raise_error(Textus::UsageError, /manifest entry missing key/)
    end

    it "derives path for a leaf entry without explicit path:" do
      entry = described_class.call({ "key" => "knowledge.notes", "lane" => "knowledge", "kind" => "leaf" })
      expect(entry.path).to eq("knowledge/notes.md")
    end

    it "derives path for a nested entry without explicit path:" do
      entry = described_class.call({ "key" => "knowledge.how-to", "lane" => "knowledge", "kind" => "nested", "nested" => true })
      expect(entry.path).to eq("knowledge/how-to")
    end

    it "derives path for a produced json entry without explicit path:" do
      entry = described_class.call({ "key" => "artifacts.derived.verbs", "lane" => "artifacts", "kind" => "produced", "format" => "json" })
      expect(entry.path).to eq("artifacts/derived/verbs.json")
    end

    it "explicit path: overrides derivation" do
      entry = described_class.call({ "key" => "knowledge.notes", "path" => "knowledge/custom-name.md", "lane" => "knowledge",
                                     "kind" => "leaf" })
      expect(entry.path).to eq("knowledge/custom-name.md")
    end

    it "defaults format to markdown when neither path nor format declared" do
      entry = described_class.call({ "key" => "knowledge.notes", "lane" => "knowledge", "kind" => "leaf" })
      expect(entry.format).to eq("markdown")
    end

    it "raises when lane is missing" do
      expect { described_class.call({ "key" => "working.foo", "path" => "foo.md" }) }
        .to raise_error(Textus::UsageError, /missing lane/)
    end

    it "raises when kind is missing" do
      expect do
        described_class.call({ "key" => "working.foo", "path" => "foo.md", "lane" => "working" })
      end.to raise_error(Textus::BadManifest, /missing required `kind:`/)
    end

    it "extracts source: from command (external)" do
      entry = described_class.call(
        {
          "key" => "output.foo", "path" => "foo.md", "lane" => "output",
          "kind" => "produced",
          "source" => { "from" => "external", "command" => "echo hi" }
        },
      )
      expect(entry).to be_a(Textus::Manifest::Entry::Produced)
      expect(entry).to be_external
    end

    it "rejects removed source.from values (fetch/derive)" do
      expect do
        described_class.call(
          {
            "key" => "output.foo", "path" => "foo.md", "lane" => "output",
            "kind" => "produced",
            "source" => { "from" => "fetch", "handler" => "h" }
          },
        )
      end.to raise_error(Textus::BadManifest, /is removed/)

      expect do
        described_class.call(
          {
            "key" => "output.foo", "path" => "foo.md", "lane" => "output",
            "kind" => "produced",
            "source" => { "from" => "weird" }
          },
        )
      end.to raise_error(Textus::BadManifest, /is removed/)
    end

    it "parses an explicit leaf row" do
      e = described_class.call({ "key" => "z.a", "path" => "z/a.md", "lane" => "z", "kind" => "leaf" })
      expect(e).to be_a(Textus::Manifest::Entry::Leaf)
    end

    it "parses an explicit nested row" do
      e = described_class.call({ "key" => "z.n", "path" => "z/n", "lane" => "z", "kind" => "nested" })
      expect(e).to be_a(Textus::Manifest::Entry::Nested)
    end

    it "raises on unknown kind" do
      expect do
        described_class.call({ "key" => "z.a", "path" => "z/a.md", "lane" => "z", "kind" => "bogus" })
      end.to raise_error(Textus::BadManifest, /unknown kind/)
    end
  end

  describe "kind: is now required (no inference fallback)" do
    it "raises BadManifest when kind: is absent, regardless of other fields" do
      expect do
        described_class.call({ "key" => "z.n", "path" => "z/n", "lane" => "z", "nested" => true })
      end.to raise_error(Textus::BadManifest, /missing required `kind:`/)

      expect do
        described_class.call({ "key" => "o.x", "path" => "o/x.md", "lane" => "o", "template" => "t.mustache" })
      end.to raise_error(Textus::BadManifest, /missing required `kind:`/)

      expect do
        described_class.call({ "key" => "z.a", "path" => "z/a.md", "lane" => "z" })
      end.to raise_error(Textus::BadManifest, /missing required `kind:`/)
    end
  end
end
