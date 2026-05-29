require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Textus::Envelope::IO::Writer.from" do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus_dir, "schemas"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}
    YAML
    Textus::Store.new(textus_dir)
  end

  it "builds a Writer wired from the container that round-trips a put" do
    Dir.mktmpdir do |root|
      textus_dir = File.join(root, ".textus")
      store = build_store(textus_dir)
      container = fresh_container(store)
      call = test_ctx(role: "runner", correlation_id: "corr-from")

      writer = Textus::Envelope::IO::Writer.from(container: container, call: call)
      expect(writer).to be_a(Textus::Envelope::IO::Writer)

      mentry = store.manifest.resolver.resolve("working.foo").entry
      env = writer.put(
        "working.foo",
        mentry: mentry,
        payload: Textus::Envelope::IO::Writer::Payload.new(meta: {}, body: "hello", content: nil),
      )

      expect(env).to be_a(Textus::Envelope)
      path = File.join(textus_dir, "zones", "working", "foo.md")
      expect(File.binread(path)).to include("hello")

      # The internally-built reader is wired correctly: reading back the entry
      # resolves the persisted uid (existing-uid lookup path).
      reader = Textus::Envelope::IO::Reader.from(container: container)
      expect(reader.existing_uid("working.foo")).to eq(env.uid)

      last = File.read(File.join(textus_dir, "audit.log")).lines.last
      expect(last).to include("\"verb\":\"put\"")
      expect(last).to include("\"correlation_id\":\"corr-from\"")
    end
  end

  it "behaves identically to a hand-wired .new" do
    Dir.mktmpdir do |root|
      textus_dir = File.join(root, ".textus")
      store = build_store(textus_dir)
      container = fresh_container(store)
      call = test_ctx(role: "runner")
      mentry = store.manifest.resolver.resolve("working.foo").entry
      payload = Textus::Envelope::IO::Writer::Payload.new(meta: {}, body: "x", content: nil)

      from_writer = Textus::Envelope::IO::Writer.from(container: container, call: call)
      hand_writer = build_envelope_writer(store, call)

      from_env = from_writer.put("working.foo", mentry: mentry, payload: payload)
      # Re-put via the hand-wired writer; uid must be preserved across both.
      hand_env = hand_writer.put("working.foo", mentry: mentry, payload: payload)

      expect(hand_env.uid).to eq(from_env.uid)
    end
  end
end
