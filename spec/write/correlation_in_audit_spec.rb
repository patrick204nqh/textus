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
        - { name: working, kind: canon }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf}

    YAML
    Textus::Store.new(textus_dir)
  end

  it "put is audit-logged with the request's correlation_id" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ops = store.as("human", correlation_id: "test-corr-put")

      ops.put(
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
      ops = store.as("human", correlation_id: "test-corr-del")

      ops.put(
        "working.foo",
        meta: { "name" => "foo" },
        body: "hello",
      )
      ops.delete("working.foo")

      row = File.readlines(File.join(root, ".textus/audit.log")).last
      parsed = JSON.parse(row)
      expect(parsed["verb"]).to eq("delete")
      expect(parsed.dig("extras", "correlation_id")).to eq("test-corr-del")
    end
  end
end
