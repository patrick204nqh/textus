require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Read::Stale do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

    YAML
    File.write(File.join(textus, "zones", "working", "doc.md"), "---\nname: doc\n---\nbody\n")
    Textus::Store.new(textus)
  end

  it "returns an Array" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      result = ops.stale
      expect(result).to be_an(Array)
    end
  end
end
