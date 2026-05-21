require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Hook loader subdirectory support" do
  def write_minimal_manifest(textus_root)
    File.write(
      File.join(textus_root, "manifest.yaml"),
      "version: textus/2\nzones:\n  - { name: working, writable_by: [human] }\nentries: []\n",
    )
  end

  it "loads hook files from nested subdirectories" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "hooks", "fetch"))
      FileUtils.mkdir_p(File.join(textus, "hooks", "reduce"))
      write_minimal_manifest(textus)

      File.write(
        File.join(textus, "hooks", "fetch", "nested_fetch.rb"),
        'Textus.fetch(:nested_fetch) { |config:, args:, **| [config, args]; { _meta: {}, body: "n" } }',
      )

      File.write(
        File.join(textus, "hooks", "reduce", "nested_reduce.rb"),
        "Textus.reduce(:nested_reduce) { |rows:, **| rows.reverse }",
      )

      store = Textus::Store.new(textus)
      registry = store.instance_variable_get(:@registry)

      expect(registry.rpc_names(:fetch)).to include(:nested_fetch)
      expect(registry.rpc_names(:reduce)).to include(:nested_reduce)
    end
  end

  it "still loads flat hooks (back-compat)" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "hooks"))
      write_minimal_manifest(textus)

      File.write(
        File.join(textus, "hooks", "flat.rb"),
        'Textus.fetch(:flat) { |config:, args:, **| [config, args]; { _meta: {}, body: "f" } }',
      )

      store = Textus::Store.new(textus)
      registry = store.instance_variable_get(:@registry)
      expect(registry.rpc_names(:fetch)).to include(:flat)
    end
  end
end
