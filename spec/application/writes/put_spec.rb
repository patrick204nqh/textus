require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Put do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "canon"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, script] }
        - { name: canon,   writable_by: [human] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working }
        - { key: canon.bar,   path: canon/bar.md,   zone: canon }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "writes the envelope when role has permission" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = Textus::Application::Context.new(store: store, role: "script")
      bus = Textus::Infra::EventBus.new(registry: store.registry)

      envelope = described_class.new(ctx: ctx, bus: bus).call(
        "working.foo",
        meta: { "key" => "working.foo" },
        body: "hello",
      )

      expect(envelope["body"] || envelope["content"]).to include("hello")
      expect(File.exist?(File.join(root, ".textus/zones/working/foo.md"))).to be(true)
    end
  end

  it "raises WriteForbidden when role lacks permission" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = Textus::Application::Context.new(store: store, role: "script")
      bus = Textus::Infra::EventBus.new(registry: store.registry)

      expect do
        described_class.new(ctx: ctx, bus: bus).call("canon.bar", meta: {}, body: "x")
      end.to raise_error(Textus::WriteForbidden)
    end
  end

  it "fires :put event with key, envelope, and correlation_id" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = Textus::Application::Context.new(store: store, role: "script", correlation_id: "corr-1")
      events = []
      store.bus.subscribe(:put, :capture) do |key:, correlation_id:, **|
        events << [:put, key, correlation_id]
      end

      described_class.new(ctx: ctx, bus: store.bus).call("working.foo", meta: {}, body: "x")

      expect(events).to include([:put, "working.foo", "corr-1"])
    end
  end
end
