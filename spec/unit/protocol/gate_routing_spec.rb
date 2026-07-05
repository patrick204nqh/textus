RSpec.describe Textus::Protocol::Gate do
  let(:policy) { instance_double(Textus::Protocol::Manifest::Policy) }
  let(:manifest) { instance_double(Manifest, resolver:, policy:) }
  let(:resolver) { instance_double("Resolver") }
  let(:store) { instance_double(Textus::Infra::Store, file_system: nil) }
  let(:store_engine) { double("StoreEngine") }
  let(:container) { double("Container", manifest:, store:, layout: nil, workflow_registry: nil) }
  let(:gate) { described_class.new(manifest:, resolver:, container:, store_engine:) }

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

      expect(handler).to receive(:ingest) do |**kwargs|
        expect(kwargs[:ctx]).to be_a(Textus::Protocol::Handlers::CommandContext)
        expect(kwargs[:ctx].store_engine).to eq(store_engine)
        expect(kwargs[:call]).to be_a(Textus::Value::Call)
      end
      gate.dispatch(:automation, :ingest, { kind: "url", slug: "test" })
    end

    it "falls through to builtin dispatch when spec has no lane" do
      get_spec = Textus::Protocol::VerbRegistry::VerbSpec.new(
        verb: :get, summary: "desc",
        args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true)],
        surfaces: %i[cli mcp], category: :read
      )
      allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:get).and_return(get_spec)
      allow(store_engine).to receive(:read).with(key: "test").and_return(nil)
      allow(resolver).to receive(:suggestions_for).with("test").and_return([])

      expect { gate.dispatch(:human, :get, { key: "test" }) }
        .to raise_error(Textus::UnknownKey)
    end
  end
end
