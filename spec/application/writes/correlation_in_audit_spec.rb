require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe "correlation_id in audit rows" do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "put is audit-logged with the request's correlation_id" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ops = Textus::Operations.for(store, role: "human", correlation_id: "test-corr-put")

      ops.writes.put.call(
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
      ops = Textus::Operations.for(store, role: "human", correlation_id: "test-corr-del")

      ops.writes.put.call(
        "working.foo",
        meta: { "name" => "foo" },
        body: "hello",
      )
      ops.writes.delete.call("working.foo")

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
        version: textus/3
        zones:
          - { name: working, write_policy: [human] }
        entries:
          - { key: working.notes, path: working/notes, zone: working, nested: true }
      YAML
      store = Textus::Store.new(File.join(root, ".textus"))

      Textus::Operations.for(store, role: "human").writes.put.call(
        "working.notes.alpha",
        meta: { "name" => "alpha" }, body: "a",
      )
      Textus::Operations.for(store, role: "human", correlation_id: "test-corr-mv").writes.mv.call(
        "working.notes.alpha", "working.notes.beta"
      )

      row = File.readlines(File.join(root, ".textus/audit.log")).last
      parsed = JSON.parse(row)
      expect(parsed["verb"]).to eq("mv")
      expect(parsed.dig("extras", "correlation_id")).to eq("test-corr-mv")
    end
  end
end
