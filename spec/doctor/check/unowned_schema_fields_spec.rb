require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::UnownedSchemaFields do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries: []
    YAML
  end

  it "returns empty array when every field declares maintained_by" do
    File.write(File.join(root, "schemas/note.yaml"), <<~YAML)
      name: note
      fields:
        title: { type: string, maintained_by: human }
    YAML
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end

  it "emits schema.unowned_fields when a field lacks maintained_by" do
    File.write(File.join(root, "schemas/note.yaml"), <<~YAML)
      name: note
      fields:
        title: { type: string, maintained_by: human }
        summary: { type: string }
    YAML
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including(
                                "code" => "schema.unowned_fields",
                                "level" => "info",
                                "subject" => "note",
                              ))
    expect(issues.first["message"]).to include("summary")
  end

  it "ignores schemas that fail to parse (handled by SchemaParseError check)" do
    File.write(File.join(root, "schemas/broken.yaml"), "::: not yaml :::")
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end
end
