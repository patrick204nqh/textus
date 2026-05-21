require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Store, ".discover" do
  let(:tmp) { Dir.mktmpdir("textus-root-spec") }

  after { FileUtils.rm_rf(tmp) }

  def make_store_at(dir)
    FileUtils.mkdir_p(File.join(dir, "schemas"))
    FileUtils.mkdir_p(File.join(dir, "zones"))
    File.write(File.join(dir, "manifest.yaml"), "version: textus/1\nzones:\n  - { name: working, writable_by: [human] }\nentries: []\n")
  end

  it "honors an explicit root: kwarg" do
    custom = File.join(tmp, "custom-root")
    make_store_at(custom)
    store = described_class.discover(root: custom)
    expect(store.root).to eq(File.expand_path(custom))
  end

  it "honors TEXTUS_ROOT when no explicit root passed" do
    custom = File.join(tmp, "envvar-root")
    make_store_at(custom)
    ENV["TEXTUS_ROOT"] = custom
    store = described_class.discover
    expect(store.root).to eq(File.expand_path(custom))
  ensure
    ENV.delete("TEXTUS_ROOT")
  end

  it "falls back to walk-from-cwd when neither is set" do
    project = File.join(tmp, "cwd-mode")
    make_store_at(File.join(project, ".textus"))
    Dir.chdir(project) do
      store = described_class.discover
      expect(store.root).to eq(File.realpath(File.join(project, ".textus")))
    end
  end

  it "raises IoError when explicit root has no manifest" do
    expect { described_class.discover(root: tmp) }.to raise_error(Textus::IoError, /manifest|no textus store/)
  end
end
