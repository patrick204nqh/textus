require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Put do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "identity"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
        - { name: identity,   write_policy: [human] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working }
        - { key: identity.bar,   path: identity/bar.md,   zone: identity }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "writes the envelope when role has permission" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "runner")
      Textus::Infra::EventBus.new(bus: store.bus)

      envelope = build_put(store, ctx).call(
        "working.foo",
        meta: { "key" => "working.foo" },
        body: "hello",
      )

      expect(envelope.body || envelope.content).to include("hello")
      expect(File.exist?(File.join(root, ".textus/zones/working/foo.md"))).to be(true)
    end
  end

  it "raises WriteForbidden when role lacks permission" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "runner")
      Textus::Infra::EventBus.new(bus: store.bus)

      expect do
        build_put(store, ctx).call("identity.bar", meta: {}, body: "x")
      end.to raise_error(Textus::WriteForbidden)
    end
  end

  it "fires :entry_put event with key, envelope, and correlation_id (via ctx)" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "runner", correlation_id: "corr-1")
      events = []
      store.bus.register(:entry_put, :capture) do |ctx:, key:, **|
        events << [:entry_put, key, ctx.correlation_id]
      end

      build_put(store, ctx).call("working.foo", meta: {}, body: "x")

      expect(events).to include([:entry_put, "working.foo", "corr-1"])
    end
  end
end
