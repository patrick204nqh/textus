require "spec_helper"

RSpec.describe Textus::Key::Path do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes: [{ name: working, kind: canon }]
      entries:
        - { key: working.x,   path: working/x.md,   lane: working, kind: leaf}

        - { key: working.dir, path: working/dir,    lane: working, kind: nested}

    YAML
  end

  it "resolves leaf entries by appending the primary extension when missing" do
    manifest = Textus::Manifest.load(root)
    entry = manifest.resolver.resolve("working.x").entry
    expect(Textus::Key::Path.resolve(manifest.data, entry)).to eq(File.join(root, "data/working/x.md"))
  end

  it "honors paths that already carry an extension" do
    manifest = Textus::Manifest.load(root)
    entry = manifest.resolver.resolve("working.x").entry
    expect(Textus::Key::Path.resolve(manifest.data, entry)).to end_with(".md")
  end
end
