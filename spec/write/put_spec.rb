require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Write::Put do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[working identity], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: quarantine }
        - { name: identity, kind: origin }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf }
        - { key: identity.bar, path: identity/bar.md, zone: identity, kind: leaf }
    YAML
  end

  it "writes the envelope when role has permission" do
    envelope = build_put(store, test_ctx(role: "automation")).call(
      "working.foo", meta: { "key" => "working.foo" }, body: "hello"
    )
    expect(envelope.body || envelope.content).to include("hello")
    expect(File.exist?(File.join(root, "zones/working/foo.md"))).to be(true)
  end

  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    # identity is an origin zone (needs the 'accept' capability); automation
    # holds only [fetch, build], so the write is genuinely refused.
    expect { build_put(store, test_ctx(role: "automation")).call("identity.bar", meta: {}, body: "x") }
      .to raise_error(
        Textus::WriteForbidden,
        /writing 'identity.bar' \(zone 'identity'\) needs capability 'accept'/,
      )
  end

  it "refuses a forbidden role with write_forbidden via the unified guard (zone_writable_by)" do
    expect { build_put(store, test_ctx(role: "automation")).call("identity.bar", meta: {}, body: "x") }
      .to raise_error(Textus::WriteForbidden) { |e| expect(e.code).to eq("write_forbidden") }
  end

  it "fires :entry_put event with key, envelope, and correlation_id (via ctx)" do
    ctx = test_ctx(role: "automation", correlation_id: "corr-1")
    events = []
    store.events.register(:entry_put, :capture) { |ctx:, key:, **| events << [:entry_put, key, ctx.correlation_id] }

    build_put(store, ctx).call("working.foo", meta: {}, body: "x")

    expect(events).to include([:entry_put, "working.foo", "corr-1"])
  end
end
