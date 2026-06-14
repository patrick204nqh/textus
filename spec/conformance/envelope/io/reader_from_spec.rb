require "spec_helper"

RSpec.describe "Textus::Envelope::IO::Reader.from" do
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

  it "builds a Reader wired from the container" do
    reader = Textus::Envelope::IO::Reader.from(container: fresh_container(store))
    expect(reader).to be_a(Textus::Envelope::IO::Reader)
  end

  it "reads an existing entry equivalently to a hand-wired .new" do
    container = fresh_container(store)
    call = test_ctx(role: "automation")
    mentry = store.manifest.resolver.resolve("knowledge.foo").entry

    writer = Textus::Envelope::IO::Writer.from(container: container, call: call)
    env = writer.put(
      "knowledge.foo",
      mentry: mentry,
      payload: Textus::Envelope::IO::Writer::Payload.new(meta: {}, body: "hello", content: nil),
    )

    from_reader = Textus::Envelope::IO::Reader.from(container: container)
    hand_reader = build_envelope_reader(store)

    expect(from_reader.read("knowledge.foo").body).to include("hello")
    expect(from_reader.existing_uid("knowledge.foo")).to eq(env.uid)
    expect(from_reader.exists?("knowledge.foo")).to be(true)
    expect(from_reader.read("knowledge.foo").uid).to eq(hand_reader.read("knowledge.foo").uid)
  end

  it "returns nil for a missing entry" do
    reader = Textus::Envelope::IO::Reader.from(container: fresh_container(store))
    expect(reader.read("knowledge.missing")).to be_nil
  end
end
