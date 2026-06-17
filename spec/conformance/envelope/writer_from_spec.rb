require "spec_helper"

RSpec.describe "Textus::Envelope::Writer.from" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, lane: knowledge, kind: leaf}
    YAML
  end

  it "builds a Writer wired from the container that round-trips a put" do
    container = fresh_container(store)
    call = test_ctx(role: "automation", correlation_id: "corr-from")

    writer = Textus::Envelope::Writer.from(container: container, call: call)
    expect(writer).to be_a(Textus::Envelope::Writer)

    mentry = store.manifest.resolver.resolve("knowledge.foo").entry
    env = writer.put(
      "knowledge.foo",
      mentry: mentry,
      payload: Textus::Envelope::Writer::Payload.new(meta: {}, body: "hello", content: nil),
    )

    expect(env).to be_a(Textus::Envelope)
    path = File.join(root, "data", "knowledge", "foo.md")
    expect(File.binread(path)).to include("hello")

    # The internally-built reader is wired correctly: reading back the entry
    # resolves the persisted uid (existing-uid lookup path).
    reader = Textus::Envelope::Reader.from(container: container)
    expect(reader.existing_uid("knowledge.foo")).to eq(env.uid)

    expect(store).to have_audit_verb("put").with_correlation("corr-from")
  end

  it "behaves identically to a hand-wired .new" do
    container = fresh_container(store)
    call = test_ctx(role: "automation")
    mentry = store.manifest.resolver.resolve("knowledge.foo").entry
    payload = Textus::Envelope::Writer::Payload.new(meta: {}, body: "x", content: nil)

    from_writer = Textus::Envelope::Writer.from(container: container, call: call)
    hand_writer = build_envelope_writer(store, call)

    from_env = from_writer.put("knowledge.foo", mentry: mentry, payload: payload)
    # Re-put via the hand-wired writer; uid must be preserved across both.
    hand_env = hand_writer.put("knowledge.foo", mentry: mentry, payload: payload)

    expect(hand_env.uid).to eq(from_env.uid)
  end
end
