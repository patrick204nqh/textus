require "spec_helper"
require "tmpdir"
require "fileutils"

# Textus::Composition was removed in v0.12.2.
# These tests are migrated to test the replacement: Textus::Operations.
# The canonical Operations spec is spec/operations_spec.rb.
RSpec.describe "Operations (formerly Composition)" do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "builds a Context with the given store and role via Operations.for" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ops = Textus::Operations.for(store, role: "runner")
      expect(ops.ctx).to be_a(Textus::Application::Context)
      expect(ops.ctx.role).to eq("runner")
    end
  end

  it "builds a reads.get use case wired to the context" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ops = Textus::Operations.for(store, role: "runner")
      expect(ops.reads.get).to be_a(Textus::Application::Reads::Get)
    end
  end
end
