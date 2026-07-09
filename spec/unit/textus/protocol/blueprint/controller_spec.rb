RSpec.describe Textus::Protocol::Blueprint::Controller do
  let(:manifest) { instance_double(Textus::Protocol::Manifest) }
  let(:resolver) { instance_double(Textus::Protocol::Manifest::Resolver) }
  let(:schemas) { instance_double(Textus::Protocol::Schema::Registry) }
  let(:mentry) do
    Textus::Protocol::Manifest::Entry::Leaf.new(
      raw: {},
      key: "knowledge.loop.intent", path: "knowledge/loop/intent.md",
      lane: "knowledge", format: "markdown", naming: "sequential", schema: nil
    )
  end
  let(:child_key) { "knowledge.loop.intent.0003-identity" }

  before do
    allow(manifest).to receive(:resolver).and_return(resolver)
    allow(resolver).to receive(:resolve).with(child_key).and_return(
      instance_double(Textus::Protocol::Manifest::Resolver::Resolution, entry: mentry)
    )
    allow(resolver).to receive(:resolve).with("knowledge.loop.intent").and_return(
      instance_double(Textus::Protocol::Manifest::Resolver::Resolution, entry: mentry)
    )
  end

  describe ".show" do
    it "returns a Blueprint for the key" do
      result = described_class.show("knowledge.loop.intent", schemas:, manifest:)
      expect(result).to be_a(Textus::Protocol::Blueprint)
      expect(result.key).to eq("knowledge.loop.intent")
    end
  end

  describe ".validate" do
    let(:payload) do
      instance_double(Textus::Value::Payload,
        meta: {}, body: "", content: nil)
    end

    it "returns empty array for child key matching naming pattern" do
      result = described_class.validate(child_key, payload, schemas:, manifest:)
      expect(result).to eq([])
    end

    context "with mismatched naming" do
      let(:bad_child_key) { "knowledge.loop.intent.bad-entry" }

      before do
        allow(resolver).to receive(:resolve).with(bad_child_key).and_return(
          instance_double(Textus::Protocol::Manifest::Resolver::Resolution, entry: mentry)
        )
      end

      it "returns naming error" do
        result = described_class.validate(bad_child_key, payload, schemas:, manifest:)
        expect(result).not_to be_empty
        expect(result.first).to include("naming violation")
      end
    end
  end

  describe ".scaffold" do
    it "returns a hash with key and body" do
      result = described_class.scaffold("knowledge.loop.intent", schemas:, manifest:)
      expect(result).to have_key(:key)
      expect(result).to have_key(:body)
    end
  end
end