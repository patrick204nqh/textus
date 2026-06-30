require "spec_helper"

RSpec.describe Textus::Links::UriRewriter do
  subject(:rewriter) { described_class.new(resolver: resolver, from_path: "docs/how-to/guide.md") }

  let(:resolver) do
    instance_double(Textus::Links::Resolver, resolve: "../reference/lanes.md")
  end

  describe "#rewrite" do
    it "rewrites a bare textus: URI in a Markdown link" do
      input  = "See [lanes](textus:artifacts.reference.lanes) for details."
      output = rewriter.rewrite(input)
      expect(output).to eq("See [lanes](../reference/lanes.md) for details.")
    end

    it "rewrites a textus: URI with an anchor" do
      allow(resolver).to receive(:resolve).and_return("../reference/lanes.md")
      input  = "[see accepted](textus:artifacts.decisions.log#accepted)"
      output = rewriter.rewrite(input)
      expect(output).to eq("[see accepted](../reference/lanes.md#accepted)")
    end

    it "passes the key and from_path to the resolver" do
      rewriter.rewrite("[lanes](textus:artifacts.reference.lanes)")
      expect(resolver).to have_received(:resolve).with(
        key: "artifacts.reference.lanes",
        from_path: "docs/how-to/guide.md",
      )
    end

    it "leaves non-textus URIs unchanged" do
      input  = "[external](https://example.com) and [local](../other.md)"
      output = rewriter.rewrite(input)
      expect(output).to eq(input)
    end

    it "handles multiple textus: URIs in one string" do
      allow(resolver).to receive(:resolve)
        .with(key: "artifacts.reference.lanes", from_path: anything)
        .and_return("../reference/lanes.md")
      allow(resolver).to receive(:resolve)
        .with(key: "artifacts.how-to.guide", from_path: anything)
        .and_return("guide.md")
      input  = "[A](textus:artifacts.reference.lanes) and [B](textus:artifacts.how-to.guide)"
      output = rewriter.rewrite(input)
      expect(output).to eq("[A](../reference/lanes.md) and [B](guide.md)")
    end

    it "falls back to textus get when resolver raises UnknownKeyError" do
      allow(resolver).to receive(:resolve)
        .and_raise(Textus::Links::Resolver::UnknownKeyError.new("unknown key: foo.bar"))
      output = rewriter.rewrite("[foo](textus:foo.bar)")
      expect(output).to eq("[foo](`textus get foo.bar`)")
    end
  end

  describe "edge recording" do
    subject(:rewriter) do
      described_class.new(
        resolver: resolver,
        from_path: "docs/how-to/guide.md",
        from_key: "artifacts.how-to.guide",
        edge_store: edge_store,
      )
    end

    let(:edge_store) { instance_double(Textus::Links::LinkEdgeStore, record: nil) }

    it "records an edge on successful resolution" do
      rewriter.rewrite("[lanes](textus:artifacts.reference.lanes)")
      expect(edge_store).to have_received(:record).with(
        from_key: "artifacts.how-to.guide",
        to_key: "artifacts.reference.lanes",
      )
    end

    it "does not record an edge when resolution raises UnknownKeyError" do
      allow(resolver).to receive(:resolve).and_raise(Textus::Links::Resolver::UnknownKeyError.new("unknown"))
      rewriter.rewrite("[foo](textus:unknown.key)")
      expect(edge_store).not_to have_received(:record)
    end
  end
end
