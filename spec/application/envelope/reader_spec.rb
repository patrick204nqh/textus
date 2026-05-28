require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Envelope::Reader do
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
        - { key: working.missing, path: working/missing.md, zone: working, kind: leaf}
    YAML
    textus_dir
  end

  def build_reader(textus_dir)
    manifest   = Textus::Manifest.load(textus_dir)
    file_store = Textus::Infra::Storage::FileStore.new
    described_class.new(file_store: file_store, manifest: manifest)
  end

  def build_writer(textus_dir, ctx)
    manifest   = Textus::Manifest.load(textus_dir)
    file_store = Textus::Infra::Storage::FileStore.new
    schemas    = Textus::Schemas.new(File.join(textus_dir, "schemas"))
    audit      = Textus::Infra::AuditLog.new(textus_dir)
    reader     = Textus::Application::Envelope::Reader.new(
      file_store: file_store, manifest: manifest,
    )
    Textus::Application::Envelope::Writer.new(
      file_store: file_store, manifest: manifest,
      schemas: schemas, audit_log: audit, ctx: ctx, reader: reader
    )
  end

  def ctx_double(role: :runner, correlation_id: nil)
    Struct.new(:role, :correlation_id).new(role, correlation_id)
  end

  def payload(meta: {}, body: nil, content: nil)
    Textus::Application::Envelope::Writer::Payload.new(
      meta: meta, body: body, content: content,
    )
  end

  describe "#read" do
    it "returns nil when the file is missing" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        reader = build_reader(textus_dir)
        expect(reader.read("working.missing")).to be_nil
      end
    end

    it "returns an envelope round-trip readable" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double
        writer = build_writer(textus_dir, ctx)
        reader = build_reader(textus_dir)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        writer.put("working.foo", mentry: mentry, payload: payload(body: "hello"))
        env = reader.read("working.foo")
        expect(env).to be_a(Textus::Envelope)
        expect(env.body).to include("hello")
      end
    end
  end

  describe "#existing_uid" do
    it "returns nil when file is missing" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        reader = build_reader(textus_dir)
        expect(reader.existing_uid("working.missing")).to be_nil
      end
    end

    it "returns the uid persisted on disk" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double
        writer = build_writer(textus_dir, ctx)
        reader = build_reader(textus_dir)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        env = writer.put("working.foo", mentry: mentry, payload: payload(body: "x"))
        expect(reader.existing_uid("working.foo")).to eq(env.uid)
      end
    end
  end

  describe "#exists?" do
    it "returns false when file is missing" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        reader = build_reader(textus_dir)
        expect(reader.exists?("working.missing")).to be(false)
      end
    end

    it "returns true once the file exists" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double
        writer = build_writer(textus_dir, ctx)
        reader = build_reader(textus_dir)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        writer.put("working.foo", mentry: mentry, payload: payload(body: "x"))
        expect(reader.exists?("working.foo")).to be(true)
      end
    end
  end
end
