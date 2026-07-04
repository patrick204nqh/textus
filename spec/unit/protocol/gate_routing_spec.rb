RSpec.describe Textus::Protocol::Gate do
  let(:manifest) { instance_double("Manifest", resolver:) }
  let(:resolver) { instance_double("Resolver") }
  let(:reader) { instance_double("Reader") }
  let(:container) { double("Container", reader:, manifest:) }
  let(:gate) { described_class.new(manifest:, resolver:, container:) }

  def lane_spec(lane:)
    Textus::Protocol::VerbRegistry::VerbSpec.new(
      verb: :ingest, summary: "desc", args: [],
      surfaces: %i[cli mcp], category: :write,
      lane:
    )
  end

  describe "dispatch routing" do
    it "calls lane handler directly when spec has lane" do
      handler = double("Handlers")
      allow(Textus::Protocol::Lane).to receive(:handler_for).with(:ingest).and_return(handler)
      allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:ingest).and_return(lane_spec(lane: :ingest))

      expect(handler).to receive(:ingest).with(hash_including(ctx: instance_of(Textus::Protocol::HandlerContext), call: anything))
      gate.dispatch(:automation, :ingest, { kind: "url", slug: "test" })
    end

    it "falls through to builtin dispatch when spec has no lane" do
      get_spec = Textus::Protocol::VerbRegistry::VerbSpec.new(
        verb: :get, summary: "desc",
        args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true)],
        surfaces: %i[cli mcp], category: :read
      )
      allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:get).and_return(get_spec)
      allow(reader).to receive(:read).with("test").and_return(nil)
      allow(resolver).to receive(:suggestions_for).with("test").and_return([])

      expect { gate.dispatch(:human, :get, { key: "test" }) }
        .to raise_error(Textus::UnknownKey)
    end
  end
end
