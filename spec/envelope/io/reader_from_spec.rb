require "spec_helper"

RSpec.describe "Textus::Envelope::IO::Reader.from" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[working], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}
        - { key: working.missing, path: working/missing.md, zone: working, kind: leaf}
    YAML
  end

  it "builds a Reader wired from the container" do
    reader = Textus::Envelope::IO::Reader.from(container: fresh_container(store))
    expect(reader).to be_a(Textus::Envelope::IO::Reader)
  end

  it "reads an existing entry equivalently to a hand-wired .new" do
    container = fresh_container(store)
    call = test_ctx(role: "automation")
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

  it "returns nil for a missing entry" do
    reader = Textus::Envelope::IO::Reader.from(container: fresh_container(store))
    expect(reader.read("working.missing")).to be_nil
  end
end
