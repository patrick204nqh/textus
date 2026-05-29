require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Textus::Envelope::IO::Reader.from" do
  def build_store(textus_dir)
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
    Textus::Store.new(textus_dir)
  end

  it "builds a Reader wired from the container" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      reader = Textus::Envelope::IO::Reader.from(container: fresh_container(store))
      expect(reader).to be_a(Textus::Envelope::IO::Reader)
    end
  end

  it "reads an existing entry equivalently to a hand-wired .new" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      container = fresh_container(store)
      call = test_ctx(role: "runner")
      mentry = store.manifest.resolver.resolve("working.foo").entry

      writer = Textus::Envelope::IO::Writer.from(container: container, call: call)
      env = writer.put(
        "working.foo",
        mentry: mentry,
        payload: Textus::Envelope::IO::Writer::Payload.new(meta: {}, body: "hello", content: nil),
      )

      from_reader = Textus::Envelope::IO::Reader.from(container: container)
      hand_reader = build_envelope_reader(store)

      expect(from_reader.read("working.foo").body).to include("hello")
      expect(from_reader.existing_uid("working.foo")).to eq(env.uid)
      expect(from_reader.exists?("working.foo")).to be(true)
      expect(from_reader.read("working.foo").uid).to eq(hand_reader.read("working.foo").uid)
    end
  end

  it "returns nil for a missing entry" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      reader = Textus::Envelope::IO::Reader.from(container: fresh_container(store))
      expect(reader.read("working.missing")).to be_nil
    end
  end
end
