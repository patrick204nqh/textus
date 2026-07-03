RSpec.describe Textus::Ingest::Resolver do
  describe ".supersede" do
    it "writes tombstone to old key and returns" do
      container = instance_double(Container)
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      reader = instance_double("Reader")
      writer = instance_double("Writer")
      entry = double("entry", entry: instance_double(Mentry))

      allow(manifest.resolver).to receive(:resolve).with("raw.2026.06.01.old").and_return(entry)
      allow(reader).to receive(:read).with("raw.2026.06.01.old").and_return(
        instance_double(Envelope, content: { "ingested_at" => "2026-06-01T00:00:00Z", "source" => { "kind" => "url" } }),
      )
      allow(container).to receive_messages(manifest:, reader:, writer:)
      allow(writer).to receive(:put)
      ctx = Textus::Protocol::HandlerContext.new(container)

      call = instance_double(Call, role: "automation", correlation_id: "abc")

      described_class.supersede("raw.2026.06.01.old", "raw.2026.07.03.new", ctx, call:)

      expect(writer).to have_received(:put).with(
        "raw.2026.06.01.old",
        mentry: entry.entry,
        if_etag: nil,
        call:,
        payload: instance_of(Textus::Value::Payload),
      )
    end

    it "handles missing old content gracefully" do
      container = instance_double(Container)
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      reader = instance_double("Reader")
      writer = instance_double("Writer")
      entry = double("entry", entry: instance_double(Mentry))

      allow(manifest.resolver).to receive(:resolve).with("raw.2026.06.01.old").and_return(entry)
      allow(reader).to receive(:read).with("raw.2026.06.01.old").and_return(nil)
      allow(container).to receive_messages(manifest:, reader:, writer:)
      allow(writer).to receive(:put)
      ctx = Textus::Protocol::HandlerContext.new(container)

      call = instance_double(Call, role: "automation", correlation_id: "abc")

      described_class.supersede("raw.2026.06.01.old", "raw.2026.07.03.new", ctx, call:)

      expect(writer).to have_received(:put)
    end
  end
end
