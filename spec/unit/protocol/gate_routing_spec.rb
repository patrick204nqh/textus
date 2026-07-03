RSpec.describe Textus::Protocol::Gate do
  let(:manifest) { instance_double("Manifest") }
  let(:resolver) { instance_double("Resolver") }
  let(:pipeline) { instance_double("Dispatch::Pipeline", container: container) }
  let(:container) { instance_double("Container") }
  let(:gate) { described_class.new(manifest:, resolver:, pipeline:) }

  def lane_spec(lane:)
    Textus::Protocol::VerbRegistry::VerbSpec.new(
      verb: :ingest, summary: "desc", args: [],
      surfaces: [:cli, :mcp], views: {default: nil},
      cli: nil, cli_stdin: nil, category: :write,
      lane:
    )
  end

  describe "dispatch routing" do
    it "calls lane handler directly when spec has lane" do
      handler = double("Handlers")
      allow(Textus::Protocol::Lane).to receive(:handler_for).with(:ingest).and_return(handler)
      allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:ingest).and_return(lane_spec(lane: :ingest))

      expect(handler).to receive(:ingest).with(hash_including(container:, call: anything))
      gate.dispatch(:agent, :ingest, {kind: "url", slug: "test"})
    end

    it "falls through to pipeline when spec has no lane" do
      read_spec = Textus::Protocol::VerbRegistry::VerbSpec.new(
        verb: :get, summary: "desc", args: [],
        surfaces: [:cli, :mcp], views: {default: nil},
        cli: nil, cli_stdin: nil, category: :read
      )
      allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:get).and_return(read_spec)

      expect(pipeline).to receive(:dispatch)
      gate.dispatch(:human, :get, {key: "test"})
    end
  end
end
