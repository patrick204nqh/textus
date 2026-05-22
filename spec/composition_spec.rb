require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Composition do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones", "working"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, script] }
    YAML
    Textus::Store.new(textus_dir)
  end

  it "builds a Context with the given store and role" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = described_class.context(store, role: "script")
      expect(ctx).to be_a(Textus::Application::Context)
      expect(ctx.role).to eq("script")
    end
  end

  it "builds a reads_get use case wired to the context" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = described_class.context(store, role: "script")
      reads_get = described_class.reads_get(ctx)
      expect(reads_get).to be_a(Textus::Application::Reads::Get)
    end
  end
end
