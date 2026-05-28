require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::ManifestFiles do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.note, path: working/note.md, zone: working, kind: leaf}

    YAML
  end

  it "returns empty array when the declared leaf file exists" do
    File.write(File.join(root, "zones/working/note.md"), "hi\n")
    store = Textus::Store.new(root)
    expect(described_class.new(Textus::Session.for(store)).call).to eq([])
  end

  it "emits manifest.missing_file when the declared leaf is absent" do
    store = Textus::Store.new(root)
    issues = described_class.new(Textus::Session.for(store)).call
    expect(issues).to include(hash_including(
                                "code" => "manifest.missing_file",
                                "level" => "info",
                                "subject" => "working.note",
                              ))
  end

  it "skips nested entries" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.notes, path: working/notes, zone: working, nested: true, kind: nested}

    YAML
    store = Textus::Store.new(root)
    expect(described_class.new(Textus::Session.for(store)).call).to eq([])
  end
end
