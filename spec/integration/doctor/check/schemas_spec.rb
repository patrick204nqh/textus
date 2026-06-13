require "spec_helper"

RSpec.describe Textus::Doctor::Check::Schemas do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, zone: knowledge, schema: note, kind: leaf}

    YAML
    File.write(File.join(root, "schemas/note.yaml"), <<~YAML)
      name: note
      required: []
      fields: {}
    YAML
  end

  it "returns empty array when all referenced schemas exist" do
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to eq([])
  end

  it "returns an error issue when a referenced schema is missing" do
    File.delete(File.join(root, "schemas/note.yaml"))
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including("code" => "schema.missing", "level" => "error"))
    expect(issues.first["fix"]).to include("note")
  end
end
