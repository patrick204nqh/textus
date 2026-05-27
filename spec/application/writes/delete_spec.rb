require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Delete do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "identity"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
        - { name: identity,   write_policy: [human] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}

        - { key: identity.bar,   path: identity/bar.md,   zone: identity, kind: leaf}

    YAML
    Textus::Store.new(textus_dir)
  end

  it "removes the entry file and fires :deleted with correlation_id" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      store = build_store(textus)
      File.write(File.join(textus, "zones", "working", "foo.md"), "---\nkey: working.foo\n---\nbody\n")

      ctx = test_ctx(role: "runner", correlation_id: "del-1")
      events = []
      store.bus.register(:entry_deleted, :capture) do |ctx:, key:, **|
        events << [:entry_deleted, key, ctx.correlation_id]
      end

      build_delete(store, ctx).call("working.foo")

      expect(File.exist?(File.join(textus, "zones", "working", "foo.md"))).to be(false)
      expect(events).to include([:entry_deleted, "working.foo", "del-1"])
    end
  end

  it "raises WriteForbidden when role lacks permission" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      store = build_store(textus)
      File.write(File.join(textus, "zones", "identity", "bar.md"), "---\nkey: identity.bar\n---\nbody\n")

      ctx = test_ctx(role: "runner")

      expect do
        build_delete(store, ctx).call("identity.bar")
      end.to raise_error(Textus::WriteForbidden)
    end
  end
end
