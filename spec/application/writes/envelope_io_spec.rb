require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::EnvelopeIO do
  def build_textus(root)
    textus_dir = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "identity"))
    FileUtils.mkdir_p(File.join(textus_dir, "schemas"))
    File.write(File.join(textus_dir, "schemas", "note.yaml"), <<~YAML)
      name: note
      required: [name, title]
      fields:
        name:  { type: string, maintained_by: human }
        title: { type: string, maintained_by: human }
      evolution:
        added_in: 2026-05-19
    YAML
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working,  write_policy: [human, runner] }
        - { name: identity, write_policy: [human] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}

        - { key: working.bar, path: working/bar.md, zone: working, kind: leaf}

        - { key: working.note, path: working/note.md, zone: working, schema: note, kind: leaf}

    YAML
    textus_dir
  end

  def build_io(textus_dir, ctx:)
    manifest   = Textus::Manifest.load(textus_dir)
    file_store = Textus::Infra::Storage::FileStore.new
    schemas    = Textus::Schemas.new(File.join(textus_dir, "schemas"))
    audit      = Textus::Infra::AuditLog.new(textus_dir)
    described_class.new(
      file_store: file_store, manifest: manifest,
      schemas: schemas, audit_log: audit, ctx: ctx
    )
  end

  def ctx_double(role: :runner, correlation_id: nil)
    Struct.new(:role, :correlation_id).new(role, correlation_id)
  end

  def payload(meta: {}, body: nil, content: nil)
    described_class::Payload.new(meta: meta, body: body, content: content)
  end

  describe "#write" do
    it "mints a uid when no prior file exists" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        env = io.write("working.foo", mentry: mentry, payload: payload(body: "hi"))

        expect(env.meta["uid"]).to be_a(String)
        expect(env.meta["uid"]).not_to be_empty
      end
    end

    it "preserves uid for existing file" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double
        io = build_io(textus_dir, ctx: ctx)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        first = io.write("working.foo", mentry: mentry, payload: payload(body: "one"))
        second = io.write("working.foo", mentry: mentry, payload: payload(body: "two"))

        expect(second.meta["uid"]).to eq(first.meta["uid"])
      end
    end

    it "enforces name-match against the path basename" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        expect do
          io.write("working.foo", mentry: mentry, payload: payload(meta: { "name" => "wrong" }, body: "x"))
        end.to raise_error(Textus::BadFrontmatter)
      end
    end

    it "validates against schema when mentry.schema is present" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.note").entry

        expect do
          io.write("working.note", mentry: mentry, payload: payload(meta: { "name" => "note" }, body: "x"))
        end.to raise_error(Textus::Error)
      end
    end

    it "skips schema validation when mentry.schema is nil" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        expect do
          io.write("working.foo", mentry: mentry, payload: payload(body: "anything"))
        end.not_to raise_error
      end
    end

    it "raises EtagMismatch when if_etag set but file does not exist" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        expect do
          io.write("working.foo", mentry: mentry, payload: payload(body: "x"), if_etag: "deadbeef")
        end.to raise_error(Textus::EtagMismatch)
      end
    end

    it "succeeds when if_etag matches the on-disk etag" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        first = io.write("working.foo", mentry: mentry, payload: payload(body: "v1"))
        env = io.write("working.foo", mentry: mentry, payload: payload(body: "v2"), if_etag: first.etag)

        expect(env.etag).not_to eq(first.etag)
      end
    end

    it "raises EtagMismatch when if_etag does not match" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        io.write("working.foo", mentry: mentry, payload: payload(body: "v1"))
        expect do
          io.write("working.foo", mentry: mentry, payload: payload(body: "v2"), if_etag: "nope")
        end.to raise_error(Textus::EtagMismatch)
      end
    end

    it "writes the file to disk (round-trip readable)" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        io.write("working.foo", mentry: mentry, payload: payload(body: "byte-for-byte"))

        path = File.join(textus_dir, "zones", "working", "foo.md")
        expect(File.exist?(path)).to be(true)
        expect(File.binread(path)).to include("byte-for-byte")
      end
    end

    it "appends an audit row with verb=put and the correlation_id" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double(role: :runner, correlation_id: "corr-99")
        io = build_io(textus_dir, ctx: ctx)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        io.write("working.foo", mentry: mentry, payload: payload(body: "hi"))

        rows = File.read(File.join(textus_dir, "audit.log")).lines
        expect(rows.last).to include("\"verb\":\"put\"")
        expect(rows.last).to include("\"correlation_id\":\"corr-99\"")
      end
    end
  end

  describe "#delete" do
    it "raises UnknownKey when the file does not exist" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        expect do
          io.delete("working.foo", mentry: mentry)
        end.to raise_error(Textus::UnknownKey)
      end
    end

    it "removes the file and audits with verb=delete and etag_after nil" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        io.write("working.foo", mentry: mentry, payload: payload(body: "hi"))
        io.delete("working.foo", mentry: mentry)

        path = File.join(textus_dir, "zones", "working", "foo.md")
        expect(File.exist?(path)).to be(false)

        rows = File.read(File.join(textus_dir, "audit.log")).lines
        expect(rows.last).to include("\"verb\":\"delete\"")
        expect(rows.last).to include("\"etag_after\":null")
      end
    end

    it "raises EtagMismatch when if_etag does not match" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        mentry = Textus::Manifest.load(textus_dir).resolver.resolve("working.foo").entry

        io.write("working.foo", mentry: mentry, payload: payload(body: "hi"))
        expect do
          io.delete("working.foo", mentry: mentry, if_etag: "wrong")
        end.to raise_error(Textus::EtagMismatch)
      end
    end
  end

  describe "#move" do
    it "moves the file to the new path, deletes the old, returns the new envelope, audits with verb=mv" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        ctx = ctx_double(role: :runner, correlation_id: "corr-mv")
        io = build_io(textus_dir, ctx: ctx)
        manifest = Textus::Manifest.load(textus_dir)
        old_mentry = manifest.resolver.resolve("working.foo").entry
        new_mentry = manifest.resolver.resolve("working.bar").entry

        io.write("working.foo", mentry: old_mentry, payload: payload(meta: { "name" => "foo" }, body: "hello"))
        envelope = io.move(from_key: "working.foo", to_key: "working.bar",
                           new_mentry: new_mentry)

        old_path = File.join(textus_dir, "zones", "working", "foo.md")
        new_path = File.join(textus_dir, "zones", "working", "bar.md")
        expect(File.exist?(old_path)).to be(false)
        expect(File.exist?(new_path)).to be(true)
        expect(envelope.key).to eq("working.bar")
        expect(envelope.uid).to be_a(String)

        rows = File.read(File.join(textus_dir, "audit.log")).lines
        mv_row = rows.find { |l| l.include?("\"verb\":\"mv\"") }
        expect(mv_row).to include("\"from_key\":\"working.foo\"")
        expect(mv_row).to include("\"to_key\":\"working.bar\"")
        expect(mv_row).to include("\"correlation_id\":\"corr-mv\"")
      end
    end

    it "raises EtagMismatch when if_etag does not match the source" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        manifest = Textus::Manifest.load(textus_dir)
        old_mentry = manifest.resolver.resolve("working.foo").entry
        new_mentry = manifest.resolver.resolve("working.bar").entry

        io.write("working.foo", mentry: old_mentry, payload: payload(meta: { "name" => "foo" }, body: "hi"))
        expect do
          io.move(from_key: "working.foo", to_key: "working.bar",
                  new_mentry: new_mentry, if_etag: "nope")
        end.to raise_error(Textus::EtagMismatch)
      end
    end

    it "preserves the UID across the move" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        manifest = Textus::Manifest.load(textus_dir)
        old_mentry = manifest.resolver.resolve("working.foo").entry
        new_mentry = manifest.resolver.resolve("working.bar").entry

        before = io.write("working.foo", mentry: old_mentry, payload: payload(meta: { "name" => "foo" }, body: "x"))
        after = io.move(from_key: "working.foo", to_key: "working.bar",
                        new_mentry: new_mentry)

        expect(after.uid).to eq(before.uid)
      end
    end

    it "raises UnknownKey when the source file does not exist" do
      Dir.mktmpdir do |root|
        textus_dir = build_textus(root)
        io = build_io(textus_dir, ctx: ctx_double)
        manifest = Textus::Manifest.load(textus_dir)
        new_mentry = manifest.resolver.resolve("working.bar").entry

        expect do
          io.move(from_key: "working.foo", to_key: "working.bar",
                  new_mentry: new_mentry)
        end.to raise_error(Textus::UnknownKey)
      end
    end
  end
end
