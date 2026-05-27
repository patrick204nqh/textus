require "spec_helper"

RSpec.describe Textus::Entry do
  describe "back-compat default surface" do
    it "Entry.parse defaults to markdown" do
      result = Textus::Entry.parse("---\ntitle: T\n---\nbody\n", path: "x.md")
      expect(result["_meta"]).to eq({ "title" => "T" })
      expect(result["body"]).to eq("body\n")
    end

    it "Entry.serialize defaults to markdown" do
      raw = Textus::Entry.serialize(meta: { "k" => "v" }, body: "b")
      expect(raw).to include("---\nk: v\n---\nb\n")
    end

    it ".for_format raises on unknown" do
      expect { Textus::Entry.for_format("xml") }.to raise_error(Textus::UsageError)
    end
  end

  describe "Manifest::Entry::Base contract" do
    def build_leaf(extra = {})
      Textus::Manifest::Entry::Leaf.new(
        manifest: nil, raw: {}, key: "working.x", path: "x.md",
        zone: "working", schema: nil, owner: "human:self", format: "markdown",
        **extra
      )
    end

    it "exposes publish_to on Base (not just on subclasses)" do
      expect(build_leaf.publish_to).to eq([])
      expect(build_leaf(publish_to: ["A.md"]).publish_to).to eq(["A.md"])
    end

    it "returns nil from Base stubs for optional cross-cutting attrs" do
      leaf = build_leaf
      expect(leaf.template).to be_nil
      expect(leaf.inject_boot).to be(false)
      expect(leaf.events).to eq({})
      expect(leaf.publish_each).to be_nil
      expect(leaf.index_filename).to be_nil
    end
  end
end
