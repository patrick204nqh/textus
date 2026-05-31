require "spec_helper"

RSpec.describe Textus::Envelope::IO::Writer do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[working], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}
        - { key: working.bar, path: working/bar.md, zone: working, kind: leaf}
    YAML
  end

  def payload(meta: {}, body: nil, content: nil)
    described_class::Payload.new(meta: meta, body: body, content: content)
  end

  describe "#put" do
    it "writes bytes, returns an envelope, and appends a 'put' audit row" do
      ctx = test_ctx(role: "automation", correlation_id: "corr-put")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("working.foo").entry

      env = writer.put("working.foo", mentry: mentry, payload: payload(body: "hi"))
      expect(env).to be_a(Textus::Envelope)
      path = File.join(root, "zones", "working", "foo.md")
      expect(File.binread(path)).to include("hi")

      expect(store).to have_audit_verb("put").with_correlation("corr-put")
    end

    it "raises EtagMismatch when if_etag does not match" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("working.foo").entry

      writer.put("working.foo", mentry: mentry, payload: payload(body: "v1"))
      expect do
        writer.put("working.foo", mentry: mentry, payload: payload(body: "v2"), if_etag: "nope")
      end.to raise_error(Textus::EtagMismatch)
    end
  end

  describe "#delete" do
    it "removes the file and appends a 'delete' audit row" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("working.foo").entry

      writer.put("working.foo", mentry: mentry, payload: payload(body: "x"))
      writer.delete("working.foo", mentry: mentry)
      path = File.join(root, "zones", "working", "foo.md")
      expect(File.exist?(path)).to be(false)

      last = File.read(audit_log_path(root)).lines.last
      expect(last).to include("\"verb\":\"delete\"")
      expect(last).to include("\"etag_after\":null")
    end

    it "raises EtagMismatch when if_etag does not match" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      mentry = store.manifest.resolver.resolve("working.foo").entry

      writer.put("working.foo", mentry: mentry, payload: payload(body: "x"))
      expect do
        writer.delete("working.foo", mentry: mentry, if_etag: "wrong")
      end.to raise_error(Textus::EtagMismatch)
    end
  end

  describe "#move" do
    it "renames file, returns envelope with new key/uid, and appends a 'mv' audit row with from_key/to_key/uid" do
      ctx = test_ctx(role: "automation", correlation_id: "corr-mv")
      writer = build_envelope_writer(store, ctx)
      old_mentry = store.manifest.resolver.resolve("working.foo").entry
      new_mentry = store.manifest.resolver.resolve("working.bar").entry

      before = writer.put(
        "working.foo", mentry: old_mentry,
                       payload: payload(meta: { "name" => "foo" }, body: "hello")
      )
      env = writer.move(from_key: "working.foo", to_key: "working.bar", new_mentry: new_mentry)

      old_path = File.join(root, "zones", "working", "foo.md")
      new_path = File.join(root, "zones", "working", "bar.md")
      expect(File.exist?(old_path)).to be(false)
      expect(File.exist?(new_path)).to be(true)
      expect(env.key).to eq("working.bar")
      expect(env.uid).to eq(before.uid)

      row = last_audit_row(store)
      expect(row["verb"]).to eq("mv")
      expect(row["from_key"]).to eq("working.foo")
      expect(row["to_key"]).to eq("working.bar")
      expect(row["uid"]).to eq(env.uid)
      expect(row.dig("extras", "correlation_id")).to eq("corr-mv")
    end

    it "raises EtagMismatch when if_etag does not match the source" do
      ctx = test_ctx(role: "automation")
      writer = build_envelope_writer(store, ctx)
      old_mentry = store.manifest.resolver.resolve("working.foo").entry
      new_mentry = store.manifest.resolver.resolve("working.bar").entry

      writer.put(
        "working.foo", mentry: old_mentry,
                       payload: payload(meta: { "name" => "foo" }, body: "x")
      )
      expect do
        writer.move(from_key: "working.foo", to_key: "working.bar",
                    new_mentry: new_mentry, if_etag: "nope")
      end.to raise_error(Textus::EtagMismatch)
    end
  end
end
