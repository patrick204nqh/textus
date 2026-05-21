require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Hook loader plugin-directory convention (0.8.3)" do
  def write_minimal_manifest(textus_root)
    File.write(
      File.join(textus_root, "manifest.yaml"),
      "version: textus/2\nzones:\n  - { name: working, writable_by: [human] }\nentries: []\n",
    )
  end

  it "prepends plugin lib/ to LOAD_PATH and requires the entry file" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      plugin = File.join(textus, "hooks", "demo_plugin")
      FileUtils.mkdir_p(File.join(plugin, "lib", "demo_plugin"))
      write_minimal_manifest(textus)

      File.write(
        File.join(plugin, "lib", "demo_plugin", "runner.rb"),
        "module DemoPluginRunner; def self.go; :ok; end; end",
      )
      File.write(
        File.join(plugin, "demo_plugin.rb"),
        <<~RUBY,
          require "demo_plugin/runner"
          Textus.fetch(:demo_plugin) { |config:, args:, **| { _meta: {}, body: DemoPluginRunner.go.to_s } }
        RUBY
      )

      store = Textus::Store.new(textus)
      registry = store.instance_variable_get(:@registry)
      expect(registry.rpc_names(:fetch)).to include(:demo_plugin)
    end
  end

  it "falls back to hook.rb when no <name>.rb entry exists" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      plugin = File.join(textus, "hooks", "fallback_plugin")
      FileUtils.mkdir_p(plugin)
      write_minimal_manifest(textus)

      File.write(
        File.join(plugin, "hook.rb"),
        "Textus.fetch(:fallback_plugin) { |config:, args:, **| { _meta: {}, body: 'ok' } }",
      )

      store = Textus::Store.new(textus)
      registry = store.instance_variable_get(:@registry)
      expect(registry.rpc_names(:fetch)).to include(:fallback_plugin)
    end
  end

  it "raises UsageError when a subdir has no entry file" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "hooks", "empty_plugin"))
      write_minimal_manifest(textus)

      expect { Textus::Store.new(textus) }.to raise_error(Textus::UsageError, /empty_plugin/)
    end
  end

  it "still loads top-level *.rb hooks alongside plugin subdirs" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      plugin = File.join(textus, "hooks", "co_plugin")
      FileUtils.mkdir_p(plugin)
      write_minimal_manifest(textus)

      File.write(
        File.join(textus, "hooks", "flat.rb"),
        "Textus.fetch(:flat) { |config:, args:, **| { _meta: {}, body: 'f' } }",
      )
      File.write(
        File.join(plugin, "co_plugin.rb"),
        "Textus.fetch(:co_plugin) { |config:, args:, **| { _meta: {}, body: 'c' } }",
      )

      store = Textus::Store.new(textus)
      registry = store.instance_variable_get(:@registry)
      names = registry.rpc_names(:fetch)
      expect(names).to include(:flat, :co_plugin)
    end
  end
end
