RSpec.describe Textus::Lanes::Ingest::Resolver do
  describe ".supersede" do
    def mock_container(manifest:, store:)
      c = double("Container")
      allow(c).to receive_messages(manifest:, store:, layout: nil, workflow_registry: nil)
      c
    end

    it "writes tombstone to old key and returns" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      entry = double("entry", entry: instance_double(Mentry))

      allow(manifest.resolver).to receive(:resolve).with("raw.2026.06.01.old").and_return(entry)
      allow(store_engine).to receive(:read).with(key: "raw.2026.06.01.old").and_return(
        instance_double(Envelope, content: { "ingested_at" => "2026-06-01T00:00:00Z", "ingest_count" => 3, "source" => { "kind" => "url" } }),
      )
      payloads = []
      allow(store_engine).to receive(:put) { |**kwargs| payloads << kwargs; nil }

      call = instance_double(Call, role: "automation", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::Context.new(container, call:)

      described_class.supersede("raw.2026.06.01.old", "raw.2026.07.03.new", store: store_engine, ctx:, call:)

      expect(payloads.last[:content]["ingested_at"]).to eq("2026-06-01T00:00:00Z")
      expect(payloads.last[:content]["ingest_count"]).to eq(3)
      expect(payloads.last[:content]["superseded_by"]).to eq("raw.2026.07.03.new")
      expect(payloads.last[:content]["source"]).to eq({ "kind" => "url" })
    end

    it "handles missing old content gracefully" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      entry = double("entry", entry: instance_double(Mentry))

      allow(manifest.resolver).to receive(:resolve).with("raw.2026.06.01.old").and_return(entry)
      allow(store_engine).to receive(:read).with(key: "raw.2026.06.01.old").and_return(nil)
      allow(store_engine).to receive(:put)

      call = instance_double(Call, role: "automation", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::Context.new(container, call:)

      described_class.supersede("raw.2026.06.01.old", "raw.2026.07.03.new", store: store_engine, ctx:, call:)

      expect(store_engine).to have_received(:put)
    end
  end
end
