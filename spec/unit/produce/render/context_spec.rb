require "spec_helper"

RSpec.describe Textus::Produce::Render::Context do
  let(:resolver)   { instance_double(Textus::Links::Resolver) }
  let(:edge_store) { instance_double(Textus::Links::LinkEdgeStore, record: nil) }

  describe ".for" do
    subject(:ctx) do
      described_class.for(
        locals: { "title" => "Hello" },
        resolver: resolver,
        from_path: "docs/foo.md",
        from_key: "artifacts.foo",
        edge_store: edge_store,
      )
    end

    it "exposes locals as methods on the returned binding" do
      result = eval("title", ctx.binding, __FILE__, __LINE__)
      expect(result).to eq("Hello")
    end

    it "exposes textus_link as a method when resolver is present" do
      allow(resolver).to receive(:resolve).with(key: "some.key", from_path: "docs/foo.md").and_return("../bar.md")
      result = eval("textus_link('some.key')", ctx.binding, __FILE__, __LINE__)
      expect(result).to eq("../bar.md")
    end

    it "records an edge in the edge_store on successful textus_link resolution" do
      allow(resolver).to receive(:resolve).and_return("../bar.md")
      eval("textus_link('some.key')", ctx.binding, __FILE__, __LINE__)
      expect(edge_store).to have_received(:record).with(from_key: "artifacts.foo", to_key: "some.key")
    end

    it "does not record an edge when resolver raises UnknownKeyError" do
      allow(resolver).to receive(:resolve).and_raise(Textus::Links::Resolver::UnknownKeyError.new("unknown"))
      eval("textus_link('missing.key')", ctx.binding, __FILE__, __LINE__)
      expect(edge_store).not_to have_received(:record)
    end

    it "falls back to backtick command when resolver raises UnknownKeyError" do
      allow(resolver).to receive(:resolve).and_raise(Textus::Links::Resolver::UnknownKeyError.new("unknown key: some.key"))
      result = eval("textus_link('some.key')", ctx.binding, __FILE__, __LINE__)
      expect(result).to eq("`textus get some.key`")
    end

    it "does not expose textus_link when resolver is nil" do
      ctx_no_resolver = described_class.for(locals: { "x" => 1 })
      expect { eval("textus_link('foo')", ctx_no_resolver.binding, __FILE__, __LINE__) }.to raise_error(NameError)
    end
  end
end
