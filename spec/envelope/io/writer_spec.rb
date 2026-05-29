require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Envelope::IO::Writer do
  def build_textus(root)
    textus_dir = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus_dir, "schemas"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}
        - { key: working.bar, path: working/bar.md, zone: working, kind: leaf}
    YAML
    textus_dir
  end

  def build_writer(textus_dir, ctx)
    manifest   = Textus::Manifest.load(textus_dir)
    file_store = Textus::Ports::Storage::FileStore.new
    schemas    = Textus::Schemas.new(File.join(textus_dir, "schemas"))
    audit      = Textus::Ports::AuditLog.new(textus_dir)
    reader     = Textus::Envelope::IO::Reader.new(
      file_store: file_store, manifest: manifest,
    )
    described_class.new(
      file_store: file_store, manifest: manifest,
      schemas: schemas, audit_log: audit, call: ctx, reader: reader
    )
  end

  def ctx_double(role: :runner, correlation_id: nil)
    Struct.new(:role, :correlation_id).new(role, correlation_id)
  end

  def payload(meta: {}, body: nil, content: nil)
    described_class::Payload.new(meta: meta, body: body, content: content)
  end

  describe "#put" do
    it "writes bytes, returns an envelope, and appends a 'put' audit row" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double(role: :runner, correlation_id: "corr-put")
        writer = build_writer(textus_dir, ctx)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        env = writer.put("working.foo", mentry: mentry, payload: payload(body: "hi"))
        expect(env).to be_a(Textus::Envelope)
        path = File.join(textus_dir, "zones", "working", "foo.md")
        expect(File.binread(path)).to include("hi")

        last = File.read(File.join(textus_dir, "audit.log")).lines.last
        expect(last).to include("\"verb\":\"put\"")
        expect(last).to include("\"correlation_id\":\"corr-put\"")
      end
    end

    it "raises EtagMismatch when if_etag does not match" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        writer = build_writer(textus_dir, ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        writer.put("working.foo", mentry: mentry, payload: payload(body: "v1"))
        expect do
          writer.put("working.foo", mentry: mentry, payload: payload(body: "v2"), if_etag: "nope")
        end.to raise_error(Textus::EtagMismatch)
      end
    end
  end

  describe "#delete" do
    it "removes the file and appends a 'delete' audit row" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        writer = build_writer(textus_dir, ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        writer.put("working.foo", mentry: mentry, payload: payload(body: "x"))
        writer.delete("working.foo", mentry: mentry)
        path = File.join(textus_dir, "zones", "working", "foo.md")
        expect(File.exist?(path)).to be(false)

        last = File.read(File.join(textus_dir, "audit.log")).lines.last
        expect(last).to include("\"verb\":\"delete\"")
        expect(last).to include("\"etag_after\":null")
      end
    end

    it "raises EtagMismatch when if_etag does not match" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        writer = build_writer(textus_dir, ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        writer.put("working.foo", mentry: mentry, payload: payload(body: "x"))
        expect do
          writer.delete("working.foo", mentry: mentry, if_etag: "wrong")
        end.to raise_error(Textus::EtagMismatch)
      end
    end
  end

  describe "#move" do
    it "renames file, returns envelope with new key/uid, and appends a 'mv' audit row with from_key/to_key/uid" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double(role: :runner, correlation_id: "corr-mv")
        writer = build_writer(textus_dir, ctx)
        manifest = Textus::Manifest.load(textus_dir)
        old_mentry = manifest.resolver.resolve("working.foo").entry
        new_mentry = manifest.resolver.resolve("working.bar").entry

        before = writer.put(
          "working.foo", mentry: old_mentry,
                         payload: payload(meta: { "name" => "foo" }, body: "hello")
        )
        env = writer.move(from_key: "working.foo", to_key: "working.bar", new_mentry: new_mentry)

        old_path = File.join(textus_dir, "zones", "working", "foo.md")
        new_path = File.join(textus_dir, "zones", "working", "bar.md")
        expect(File.exist?(old_path)).to be(false)
        expect(File.exist?(new_path)).to be(true)
        expect(env.key).to eq("working.bar")
        expect(env.uid).to eq(before.uid)

        mv_row = File.read(File.join(textus_dir, "audit.log")).lines
                     .find { |l| l.include?("\"verb\":\"mv\"") }
        expect(mv_row).to include("\"from_key\":\"working.foo\"")
        expect(mv_row).to include("\"to_key\":\"working.bar\"")
        expect(mv_row).to include("\"uid\":\"#{env.uid}\"")
        expect(mv_row).to include("\"correlation_id\":\"corr-mv\"")
      end
    end

    it "raises EtagMismatch when if_etag does not match the source" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        writer = build_writer(textus_dir, ctx_double)
        manifest = Textus::Manifest.load(textus_dir)
        old_mentry = manifest.resolver.resolve("working.foo").entry
        new_mentry = manifest.resolver.resolve("working.bar").entry

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
end
