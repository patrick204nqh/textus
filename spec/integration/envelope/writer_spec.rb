require "spec_helper"

RSpec.describe Textus::Envelope::Writer do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, lane: knowledge, kind: leaf}
        - { key: knowledge.bar, path: knowledge/bar.md, lane: knowledge, kind: leaf}
    YAML
  end

  def payload(meta: {}, body: nil, content: nil)
    described_class::Payload.new(meta: meta, body: body, content: content)
  end

  describe "#put" do
    it "writes bytes, returns an envelope, and appends a 'put' audit row" do
      ctx = test_ctx(role: "automation", correlation_id: "corr-put")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("knowledge.foo").entry

      env = writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "hi"))
      expect(env).to be_a(Textus::Value::Envelope)
      path = File.join(root, "data", "knowledge", "foo.md")
      expect(File.binread(path)).to include("hi")

      expect(store).to have_audit_verb("put").with_correlation("corr-put")
    end

    it "raises EtagMismatch when if_etag does not match" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("knowledge.foo").entry

      writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "v1"))
      expect do
        writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "v2"), if_etag: "nope")
      end.to raise_error(Textus::EtagMismatch)
    end
  end

  describe "#delete" do
    it "removes the file and appends a 'delete' audit row" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("knowledge.foo").entry

      writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "x"))
      writer.delete("knowledge.foo", mentry: mentry)
      path = File.join(root, "data", "knowledge", "foo.md")
      expect(File.exist?(path)).to be(false)

      last = File.read(audit_log_path(root)).lines.last
      expect(last).to include("\"verb\":\"key_delete\"")
      expect(last).to include("\"etag_after\":null")
    end

    it "raises EtagMismatch when if_etag does not match" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("knowledge.foo").entry

      writer.put("knowledge.foo", mentry: mentry, payload: payload(body: "x"))
      expect do
        writer.delete("knowledge.foo", mentry: mentry, if_etag: "wrong")
      end.to raise_error(Textus::EtagMismatch)
    end
  end

  describe "#move" do
    it "renames file, returns envelope with new key/uid, and appends a 'mv' audit row with from_key/to_key/uid", :aggregate_failures do
      ctx = test_ctx(role: "automation", correlation_id: "corr-mv")
      writer = build_envelope_writer(store, ctx)
      old_mentry = store.manifest.resolver.resolve("knowledge.foo").entry
      new_mentry = store.manifest.resolver.resolve("knowledge.bar").entry

      before = writer.put(
        "knowledge.foo", mentry: old_mentry,
                         payload: payload(meta: { "name" => "foo" }, body: "hello")
      )
      env = writer.move(from_key: "knowledge.foo", to_key: "knowledge.bar", new_mentry: new_mentry)

      old_path = File.join(root, "data", "knowledge", "foo.md")
      new_path = File.join(root, "data", "knowledge", "bar.md")
      expect(File.exist?(old_path)).to be(false)
      expect(File.exist?(new_path)).to be(true)
      expect(env.key).to eq("knowledge.bar")
      expect(env.uid).to eq(before.uid)

      row = last_audit_row(store)
      expect(row["verb"]).to eq("key_mv")
      expect(row["from_key"]).to eq("knowledge.foo")
      expect(row["to_key"]).to eq("knowledge.bar")
      expect(row["uid"]).to eq(env.uid)
      expect(row.dig("extras", "correlation_id")).to eq("corr-mv")
    end

    it "raises EtagMismatch when if_etag does not match the source" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      old_mentry = store.manifest.resolver.resolve("knowledge.foo").entry
      new_mentry = store.manifest.resolver.resolve("knowledge.bar").entry

      writer.put(
        "knowledge.foo", mentry: old_mentry,
                         payload: payload(meta: { "name" => "foo" }, body: "x")
      )
      expect do
        writer.move(from_key: "knowledge.foo", to_key: "knowledge.bar",
                    new_mentry: new_mentry, if_etag: "nope")
      end.to raise_error(Textus::EtagMismatch)
    end
  end
end
