require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Key::Path do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x,   path: working/x.md,   zone: working }
        - { key: working.dir, path: working/dir,    zone: working, nested: true }
    YAML
  end

  it "resolves leaf entries by appending the primary extension when missing" do
    manifest = Textus::Manifest.load(root)
    entry, = manifest.resolve("working.x")
    expect(Textus::Key::Path.resolve(manifest, entry)).to eq(File.join(root, "zones/working/x.md"))
  end

  it "honors paths that already carry an extension" do
    manifest = Textus::Manifest.load(root)
    entry, = manifest.resolve("working.x")
    expect(Textus::Key::Path.resolve(manifest, entry)).to end_with(".md")
  end
end
