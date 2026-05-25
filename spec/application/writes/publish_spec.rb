require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Publish do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones/identity"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "copies the source to the target path" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      store = build_store(textus)

      source = File.join(textus, "zones/identity/src.md")
      target = File.join(root, "dist", "src.md")
      File.write(source, "hello textus")

      ctx = Textus::Application::Context.new(store: store, role: "human")
      described_class.new(ctx: ctx, bus: store.bus).call(source: source, target: target, key: "identity.src")

      expect(File.read(target)).to eq("hello textus")
    end
  end

  it "fires :published event with key and correlation_id" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      store = build_store(textus)

      source = File.join(textus, "zones/identity/note.md")
      target = File.join(root, "out", "note.md")
      File.write(source, "content")

      ctx = Textus::Application::Context.new(store: store, role: "human", correlation_id: "pub-1")
      events = []
      store.bus.subscribe(:published, :capture_publish) do |key:, correlation_id:, **|
        events << { key: key, correlation_id: correlation_id }
      end

      described_class.new(ctx: ctx, bus: store.bus).call(source: source, target: target, key: "identity.note")

      expect(events.length).to eq(1)
      expect(events.first[:key]).to eq("identity.note")
      expect(events.first[:correlation_id]).to eq("pub-1")
    end
  end

  it "includes source and target in the :published event" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      store = build_store(textus)

      source = File.join(textus, "zones/identity/doc.md")
      target = File.join(root, "pub", "doc.md")
      File.write(source, "doc content")

      ctx = Textus::Application::Context.new(store: store, role: "human", correlation_id: "pub-2")
      events = []
      store.bus.subscribe(:published, :capture_paths) do |source:, target:, **|
        events << { source: source, target: target }
      end

      described_class.new(ctx: ctx, bus: store.bus).call(source: source, target: target, key: "identity.doc")

      expect(events.first[:source]).to eq(source)
      expect(events.first[:target]).to eq(target)
    end
  end

  it "raises PublishError when target exists and is not managed" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      store = build_store(textus)

      source = File.join(textus, "zones/identity/item.md")
      target = File.join(root, "item.md")
      File.write(source, "new content")
      File.write(target, "pre-existing unmanaged content")

      ctx = Textus::Application::Context.new(store: store, role: "human")
      expect do
        described_class.new(ctx: ctx, bus: store.bus).call(source: source, target: target, key: "identity.item")
      end.to raise_error(Textus::PublishError, /unmanaged/)
    end
  end
end
