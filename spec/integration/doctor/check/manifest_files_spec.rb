require "spec_helper"

RSpec.describe Textus::Doctor::Check::ManifestFiles do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, kind: leaf}

    YAML
  end

  it "returns empty array when the declared leaf file exists" do
    File.write(File.join(root, "data/knowledge/note.md"), "hi\n")
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end

  it "emits manifest.missing_file when the declared leaf is absent" do
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including(
                                "code" => "manifest.missing_file",
                                "level" => "info",
                                "subject" => "knowledge.note",
                              ))
  end

  it "skips nested entries" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, lane: knowledge, kind: nested}

    YAML
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end
end
