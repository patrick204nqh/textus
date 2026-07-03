RSpec.describe Textus::Protocol::Gate do
  let(:manifest) { instance_double("Manifest") }
  let(:resolver) { instance_double("Resolver") }
  let(:pipeline) { double("pipeline", container: double("Container", reader:)) }
  let(:reader) { instance_double("Reader") }
  let(:gate) { described_class.new(manifest:, resolver:, pipeline:) }

  def lane_spec(lane:)
    Textus::Protocol::VerbRegistry::VerbSpec.new(
      verb: :ingest, summary: "desc", args: [],
      surfaces: %i[cli mcp], views: { default: nil },
      cli: nil, cli_stdin: nil, category: :write,
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
        surfaces: %i[cli mcp], views: { default: nil },
        cli: nil, cli_stdin: nil, category: :read
      )
      allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:get).and_return(get_spec)
      allow(reader).to receive(:read).with("test").and_return(nil)

      result = gate.dispatch(:human, :get, { key: "test" })
      expect(result).to be_a(Hash)
    end
  end
end
