require "spec_helper"

RSpec.describe Textus::Produce::Render::Context do
  let(:resolver) { instance_double(Textus::Links::Resolver) }

  describe ".for" do
    subject(:ctx) { described_class.for(locals: { "title" => "Hello" }, resolver: resolver, from_path: "docs/foo.md") }

    it "exposes locals as methods on the returned binding" do
      result = eval("title", ctx.binding, __FILE__, __LINE__)
      expect(result).to eq("Hello")
    end

    it "exposes textus_link as a method when resolver is present" do
      allow(resolver).to receive(:resolve).with(key: "some.key", from_path: "docs/foo.md").and_return("../bar.md")
      result = eval("textus_link('some.key')", ctx.binding, __FILE__, __LINE__)
      expect(result).to eq("../bar.md")
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
