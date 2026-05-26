require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Reads::Where do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working, owner: alice }
    YAML
    File.write(File.join(textus, "zones", "working", "doc.md"), "---\nname: doc\n---\nbody\n")
    Textus::Store.new(textus)
  end

  it "returns a hash with protocol, key, zone, owner, path for a known key" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = Textus::Operations.for(store, role: "human")
      result = ops.where("working.doc")

      expect(result).to include(
        "protocol" => be_a(String),
        "key" => "working.doc",
        "zone" => "working",
        "owner" => "alice",
        "path" => end_with("working/doc.md"),
      )
    end
  end
end
