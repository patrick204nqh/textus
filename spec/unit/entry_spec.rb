require "spec_helper"

RSpec.describe Textus::Format do
  describe "back-compat default surface" do
    it "Entry.parse defaults to markdown" do
      result = Textus::Format.parse("---\ntitle: T\n---\nbody\n", path: "x.md")
      expect(result["_meta"]).to eq({ "title" => "T" })
      expect(result["body"]).to eq("body\n")
    end

    it "Entry.serialize defaults to markdown" do
      raw = Textus::Format.serialize(meta: { "k" => "v" }, body: "b")
      expect(raw).to include("---\nk: v\n---\nb\n")
    end

    it ".for raises on unknown" do
      expect { Textus::Format.for("xml") }.to raise_error(Textus::UsageError)
    end
  end

  describe "Manifest::Entry::Base contract" do
    def build_leaf(extra = {})
      Textus::Manifest::Entry::Leaf.new(
        raw: {}, key: "working.x", path: "x.md",
        lane: "working", schema: nil, owner: "human:self", format: "markdown",
        **extra
      )
    end

    it "exposes publish_to on Base (not just on subclasses)" do
      expect(build_leaf.publish_to).to eq([])
      target = Textus::Manifest::Policy::PublishTarget.new("to" => "A.md")
      expect(build_leaf(publish_targets: [target]).publish_to).to eq(["A.md"])
    end

    it "returns defaults from Base stubs for optional cross-cutting attrs" do
      leaf = build_leaf
      expect(leaf.events).to eq({})
      expect(leaf.ignore).to eq([])
      expect(leaf.publish_tree).to be_nil
    end

    it "answers production-trait predicates falsey on Base (Produced overrides)" do
      leaf = build_leaf
      expect(leaf.external?).to be(false)
      expect(leaf.projection?).to be(false)
    end
  end

  describe "Manifest::Entry::REGISTRY" do
    it "registers all kinds at load (ADR 0095: derived+intake folded into produced)" do
      expect(Textus::Manifest::Entry::REGISTRY.keys).to contain_exactly(:leaf, :nested, :produced)
    end

    it "maps each kind to its class" do
      expect(Textus::Manifest::Entry::REGISTRY[:leaf]).to eq(Textus::Manifest::Entry::Leaf)
      expect(Textus::Manifest::Entry::REGISTRY[:nested]).to eq(Textus::Manifest::Entry::Nested)
      expect(Textus::Manifest::Entry::REGISTRY[:produced]).to eq(Textus::Manifest::Entry::Produced)
    end
  end
end
