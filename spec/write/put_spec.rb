require "spec_helper"

RSpec.describe Textus::Write::Put do
  include_context "textus_store_fixture"

  let(:store) { quarantine_store(root) }

  it "writes the envelope when role has permission" do
    envelope = store.as("automation").put(
      "working.foo", meta: { "key" => "working.foo" }, body: "hello"
    )
    expect(envelope.body || envelope.content).to include("hello")
    expect(File.exist?(File.join(root, "zones/working/foo.md"))).to be(true)
  end

  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    # identity is a canon zone (needs the 'author' capability); automation
    # holds only [fetch, build], so the write is genuinely refused.
    expect { store.as("automation").put("identity.bar", meta: {}, body: "x") }
      .to raise_error(
        Textus::WriteForbidden,
        /writing 'identity.bar' \(zone 'identity'\) needs capability 'author'/,
      )
  end

  it "refuses a forbidden role with write_forbidden via the unified guard (zone_writable_by)" do
    expect { store.as("automation").put("identity.bar", meta: {}, body: "x") }
      .to raise_error(Textus::WriteForbidden) { |e| expect(e.code).to eq("write_forbidden") }
  end

  it "fires :entry_put event with key, envelope, and correlation_id (via ctx)" do
    events = []
    store.events.register(:entry_put, :capture) { |ctx:, key:, **| events << [:entry_put, key, ctx.correlation_id] }

    store.as("automation", correlation_id: "corr-1").put("working.foo", meta: {}, body: "x")

    expect(events).to include([:entry_put, "working.foo", "corr-1"])
  end
end
