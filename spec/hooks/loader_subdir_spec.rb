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
      FileUtils.mkdir_p(File.join(textus, "hooks", "intake"))
      FileUtils.mkdir_p(File.join(textus, "hooks", "reduce"))
      write_minimal_manifest(textus)

      File.write(
        File.join(textus, "hooks", "intake", "nested_intake.rb"),
        'Textus.intake(:nested_intake) { |config:, args:, **| [config, args]; { _meta: {}, body: "n" } }',
      )

      File.write(
        File.join(textus, "hooks", "reduce", "nested_reduce.rb"),
        "Textus.reduce(:nested_reduce) { |rows:, **| rows.reverse }",
      )

      store = Textus::Store.new(textus)
      registry = store.instance_variable_get(:@registry)

      expect(registry.rpc_names(:intake)).to include(:nested_intake)
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
        'Textus.intake(:flat) { |config:, args:, **| [config, args]; { _meta: {}, body: "f" } }',
      )

      store = Textus::Store.new(textus)
      registry = store.instance_variable_get(:@registry)
      expect(registry.rpc_names(:intake)).to include(:flat)
    end
  end
end
