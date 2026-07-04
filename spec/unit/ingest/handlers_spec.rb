RSpec.describe Textus::Lanes::Ingest::Handlers do
  def mock_container(manifest:, store:, layout: nil)
    c = double("Container")
    allow(c).to receive_messages(manifest:, store:, layout:)
    c
  end

  def mock_entry_store(store, entry_store)
    allow(Textus::Protocol::EntryStore).to receive(:new)
      .with(file_system: store.file_system, manifest: anything, layout: anything, store: store)
      .and_return(entry_store)
  end

  describe ".ingest" do
    it "validates kind and calls sub-components" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      entry_store = instance_double(Textus::Protocol::EntryStore)
      event_store = instance_double("EventStore")
      store = instance_double(Textus::Infra::Store, db: event_store, file_system: nil)
      layout = instance_double("Layout")
      container = mock_container(manifest:, store:, layout:)
      mock_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)
      call = instance_double(Call, role: "agent", correlation_id: "abc")

      entry = double("entry", entry: instance_double(Mentry, format: "yaml", lane: "raw"))
      allow(manifest.resolver).to receive(:resolve).and_return(entry)

      allow(Textus::Lanes::Ingest::KeyBuilder).to receive_messages(derive_key: "raw.2026.07.03.url-test", compute_hash: "sha256:abc123")
      allow(Textus::Lanes::Ingest::EntryTypes).to receive(:for).with("url").and_return(Textus::Lanes::Ingest::EntryTypes::Link)
      allow(Textus::Lanes::Ingest::Dedup).to receive(:find).and_return(nil)
      allow(entry_store).to receive(:put).and_return(instance_double(Envelope, uid: "uid123", etag: "etag456"))
      allow(entry_store).to receive(:read)
      allow(Textus::Lanes::Ingest::IndexRebuilder).to receive(:rebuild!)

      allow(Time).to receive(:now).and_return(Time.new(2026, 7, 3, 12, 0, 0, "UTC"))

      described_class.ingest(
        kind: "url", slug: "test-link", url: "https://example.com",
        ctx:, call:
      )

      expect(entry_store).to have_received(:put).with(
        "raw.2026.07.03.url-test",
        mentry: entry.entry,
        if_etag: nil,
        call:,
        payload: instance_of(Textus::Value::Payload),
      )
      expect(Textus::Lanes::Ingest::IndexRebuilder).to have_received(:rebuild!)
    end

    it "handles duplicate by superseding" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      entry_store = instance_double(Textus::Protocol::EntryStore)
      event_store = instance_double("EventStore")
      store = instance_double(Textus::Infra::Store, db: event_store, file_system: nil)
      layout = instance_double("Layout")
      container = mock_container(manifest:, store:, layout:)
      mock_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)
      call = instance_double(Call, role: "agent", correlation_id: "abc")

      entry = double("entry", entry: instance_double(Mentry, format: "yaml", lane: "raw"))
      allow(manifest.resolver).to receive(:resolve).with("raw.2026.07.03.url-test").and_return(entry)
      allow(manifest.resolver).to receive(:resolve).with("raw.2026.06.01.old").and_return(entry)

      allow(Textus::Lanes::Ingest::KeyBuilder).to receive_messages(derive_key: "raw.2026.07.03.url-test", compute_hash: "sha256:dup")
      allow(Textus::Lanes::Ingest::EntryTypes).to receive(:for).with("url").and_return(Textus::Lanes::Ingest::EntryTypes::Link)
      allow(Textus::Lanes::Ingest::Dedup).to receive(:find).and_return("raw.2026.06.01.old")
      allow(Textus::Lanes::Ingest::Resolver).to receive(:supersede)
      allow(entry_store).to receive(:put).and_return(instance_double(Envelope, uid: "uid456", etag: "etag789"))
      allow(entry_store).to receive(:read)
      allow(Textus::Lanes::Ingest::IndexRebuilder).to receive(:rebuild!)

      allow(Time).to receive(:now).and_return(Time.new(2026, 7, 3, 12, 0, 0, "UTC"))

      described_class.ingest(
        kind: "url", slug: "test-link", url: "https://example.com",
        ctx:, call:
      )

      expect(Textus::Lanes::Ingest::Resolver).to have_received(:supersede).with(
        "raw.2026.06.01.old", "raw.2026.07.03.url-test", ctx, call:
      )
    end

    it "returns failure for invalid kind" do
      container = double("Container")
      ctx = Textus::Protocol::HandlerContext.new(container)
      call = instance_double(Call)

      expect { described_class.ingest(kind: "invalid", slug: "test", ctx:, call:) }
        .to raise_error(Textus::UsageError, /kind must be one of/)
    end
  end
end
