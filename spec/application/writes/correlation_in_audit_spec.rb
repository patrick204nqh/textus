require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe "correlation_id in audit rows" do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, script] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "put is audit-logged with the request's correlation_id" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = Textus::Application::Context.new(
        store: store, role: "human", correlation_id: "test-corr-put",
      )

      Textus::Composition.writes_put(ctx).call(
        "working.foo",
        meta: { "name" => "foo" },
        body: "hello",
      )

      row = File.readlines(File.join(root, ".textus/audit.log")).last
      parsed = JSON.parse(row)
      expect(parsed["verb"]).to eq("put")
      expect(parsed.dig("extras", "correlation_id")).to eq("test-corr-put")
    end
  end

  it "delete is audit-logged with the request's correlation_id" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = Textus::Application::Context.new(
        store: store, role: "human", correlation_id: "test-corr-del",
      )

      Textus::Composition.writes_put(ctx).call(
        "working.foo",
        meta: { "name" => "foo" },
        body: "hello",
      )
      Textus::Composition.writes_delete(ctx).call("working.foo")

      row = File.readlines(File.join(root, ".textus/audit.log")).last
      parsed = JSON.parse(row)
      expect(parsed["verb"]).to eq("delete")
      expect(parsed.dig("extras", "correlation_id")).to eq("test-corr-del")
    end
  end

  it "mv is audit-logged with the caller-provided correlation_id" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".textus", "zones", "working"))
      File.write(File.join(root, ".textus", "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: working, writable_by: [human] }
        entries:
          - { key: working.notes, path: working/notes, zone: working, nested: true }
      YAML
      store = Textus::Store.new(File.join(root, ".textus"))

      store.put("working.notes.alpha",
                meta: { "name" => "alpha" }, body: "a", as: "human")
      store.mv("working.notes.alpha", "working.notes.beta",
               as: "human", correlation_id: "test-corr-mv")

      row = File.readlines(File.join(root, ".textus/audit.log")).last
      parsed = JSON.parse(row)
      expect(parsed["verb"]).to eq("mv")
      expect(parsed.dig("extras", "correlation_id")).to eq("test-corr-mv")
    end
  end
end
