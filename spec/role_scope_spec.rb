require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Textus::RoleScope do
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

  it "Store#as(role) returns a RoleScope bound to that role" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      scope = store.as("human")
      expect(scope).to be_a(Textus::RoleScope)
      expect(scope.role).to eq("human")
    end
  end

  it "Store#as(role).put writes and Store#as(role).get reads back" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      result = store.as("human").put(
        "working.foo",
        meta: { "name" => "foo" },
        body: "hello-rolescope",
      )
      expect(result).not_to be_nil

      env = store.as("human").get("working.foo")
      expect(env).not_to be_nil
      expect(env.body.strip).to eq("hello-rolescope")
    end
  end

  it "passes correlation_id: through to the audit record" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      store.as("human", correlation_id: "test-corr-rolescope").put(
        "working.foo",
        meta: { "name" => "foo" },
        body: "hi",
      )

      row = File.readlines(File.join(root, ".textus/audit.log")).last
      parsed = JSON.parse(row)
      expect(parsed["verb"]).to eq("put")
      expect(parsed.dig("extras", "correlation_id")).to eq("test-corr-rolescope")
    end
  end

  it "#with_role returns a new RoleScope with the given role" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      scope = store.as("human").with_role("automation")
      expect(scope).to be_a(Textus::RoleScope)
      expect(scope.role).to eq("automation")
    end
  end

  it "#with_dry_run returns a RoleScope with dry_run=true" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      scope = store.as("human").with_dry_run
      expect(scope).to be_a(Textus::RoleScope)
      expect(scope.dry_run?).to be(true)
    end
  end

  it "Store#put delegates to the default role's RoleScope" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      store.put("working.foo", role: "human", meta: { "name" => "foo" }, body: "default")
      env = store.get("working.foo")
      expect(env.body.strip).to eq("default")
    end
  end
end
