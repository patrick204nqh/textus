require "spec_helper"

RSpec.describe Textus::Envelope::IO::Reader do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: data/knowledge/foo.md, lane: knowledge, kind: leaf}
        - { key: knowledge.missing, path: data/knowledge/missing.md, lane: knowledge, kind: leaf}
    YAML
  end

  def payload(meta: {}, body: nil, content: nil)
    Textus::Envelope::IO::Writer::Payload.new(
      meta: meta, body: body, content: content,
    )
  end

  describe "#read" do
    it "returns nil when the file is missing" do
      reader = build_envelope_reader(store)
      expect(reader.read("knowledge.missing")).to be_nil
    end

    it "returns an envelope round-trip readable" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      reader = build_envelope_reader(store)
      mentry = store.manifest.resolver.resolve("knowledge.foo").entry

      writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "hello"))
      env = reader.read("knowledge.foo")
      expect(env).to be_a(Textus::Envelope)
      expect(env.body).to include("hello")
    end
  end

  describe "#existing_uid" do
    it "returns nil when file is missing" do
      reader = build_envelope_reader(store)
      expect(reader.existing_uid("knowledge.missing")).to be_nil
    end

    it "returns the uid persisted on disk" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      reader = build_envelope_reader(store)
      mentry = store.manifest.resolver.resolve("knowledge.foo").entry

      env = writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "x"))
      expect(reader.existing_uid("knowledge.foo")).to eq(env.uid)
    end
  end

  describe "#exists?" do
    it "returns false when file is missing" do
      reader = build_envelope_reader(store)
      expect(reader.exists?("knowledge.missing")).to be(false)
    end

    it "returns true once the file exists" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      reader = build_envelope_reader(store)
      mentry = store.manifest.resolver.resolve("knowledge.foo").entry

      writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "x"))
      expect(reader.exists?("knowledge.foo")).to be(true)
    end
  end
end
