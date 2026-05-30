require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Write::Put do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "identity"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: quarantine }
        - { name: identity,   kind: origin }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}

        - { key: identity.bar,   path: identity/bar.md,   zone: identity, kind: leaf}

    YAML
    Textus::Store.new(textus_dir)
  end

  it "writes the envelope when role has permission" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "automation")

      envelope = build_put(store, ctx).call(
        "working.foo",
        meta: { "key" => "working.foo" },
        body: "hello",
      )

      expect(envelope.body || envelope.content).to include("hello")
      expect(File.exist?(File.join(root, ".textus/zones/working/foo.md"))).to be(true)
    end
  end

  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      # identity is an origin zone (needs the 'accept' capability); automation
      # holds only [fetch, build], so the write is genuinely refused.
      ctx = test_ctx(role: "automation")

      expect do
        build_put(store, ctx).call("identity.bar", meta: {}, body: "x")
      end.to raise_error(
        Textus::WriteForbidden,
        /writing 'identity.bar' \(zone 'identity'\) needs capability 'accept'/,
      )
    end
  end

  it "refuses a forbidden role with write_forbidden via the unified guard (zone_writable_by)" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      expect { build_put(store, test_ctx(role: "automation")).call("identity.bar", meta: {}, body: "x") }
        .to raise_error(Textus::WriteForbidden) { |e| expect(e.code).to eq("write_forbidden") }
    end
  end

  it "fires :entry_put event with key, envelope, and correlation_id (via ctx)" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "automation", correlation_id: "corr-1")
      events = []
      store.events.register(:entry_put, :capture) do |ctx:, key:, **|
        events << [:entry_put, key, ctx.correlation_id]
      end

      build_put(store, ctx).call("working.foo", meta: {}, body: "x")

      expect(events).to include([:entry_put, "working.foo", "corr-1"])
    end
  end
end
