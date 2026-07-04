RSpec.describe Textus::Lanes::Ingest::Resolver do
  describe ".supersede" do
    def mock_container(manifest:, store:)
      c = double("Container")
      allow(c).to receive_messages(manifest:, store:, layout: nil)
      c
    end

    def with_entry_store(store, entry_store)
      allow(Textus::Protocol::EntryStore).to receive(:new)
        .with(file_system: store.file_system, manifest: anything, layout: anything, store: store)
        .and_return(entry_store)
    end

    it "writes tombstone to old key and returns" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      entry = double("entry", entry: instance_double(Mentry))

      with_entry_store(store, entry_store)

      allow(manifest.resolver).to receive(:resolve).with("raw.2026.06.01.old").and_return(entry)
      allow(entry_store).to receive(:read).with("raw.2026.06.01.old").and_return(
        instance_double(Envelope, content: { "ingested_at" => "2026-06-01T00:00:00Z", "source" => { "kind" => "url" } }),
      )
      allow(entry_store).to receive(:put)
      ctx = Textus::Protocol::HandlerContext.new(container)

      call = instance_double(Call, role: "automation", correlation_id: "abc")

      described_class.supersede("raw.2026.06.01.old", "raw.2026.07.03.new", ctx, call:)

      expect(entry_store).to have_received(:put).with(
        "raw.2026.06.01.old",
        mentry: entry.entry,
        if_etag: nil,
        call:,
        payload: instance_of(Textus::Value::Payload),
      )
    end

    it "handles missing old content gracefully" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      entry = double("entry", entry: instance_double(Mentry))

      with_entry_store(store, entry_store)

      allow(manifest.resolver).to receive(:resolve).with("raw.2026.06.01.old").and_return(entry)
      allow(entry_store).to receive(:read).with("raw.2026.06.01.old").and_return(nil)
      allow(entry_store).to receive(:put)
      ctx = Textus::Protocol::HandlerContext.new(container)

      call = instance_double(Call, role: "automation", correlation_id: "abc")

      described_class.supersede("raw.2026.06.01.old", "raw.2026.07.03.new", ctx, call:)

      expect(entry_store).to have_received(:put)
    end
  end
end
