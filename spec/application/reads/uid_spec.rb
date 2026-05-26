require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Reads::Uid do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working }
    YAML
    File.write(File.join(textus, "zones", "working", "doc.md"), <<~MD)
      ---
      uid: "abc123def456"
      name: doc
      ---
      body
    MD
    Textus::Store.new(textus)
  end

  it "returns the uid declared in the entry frontmatter" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = Textus::Operations.for(store, role: "human")
      result = ops.uid("working.doc")
      expect(result).to eq("abc123def456")
    end
  end
end
