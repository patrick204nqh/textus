require "spec_helper"

RSpec.describe Textus::Doctor::Check::SchemaParseError do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries: []
    YAML
  end

  it "returns empty array when every schema parses cleanly" do
    File.write(File.join(root, "schemas/note.yaml"), <<~YAML)
      name: note
      fields:
        title: { type: string, maintained_by: human }
    YAML
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end

  it "returns empty array when the schemas directory does not exist" do
    FileUtils.rm_rf(File.join(root, "schemas"))
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end

  it "emits schema.parse_error for invalid YAML" do
    bad = File.join(root, "schemas/broken.yaml")
    File.write(bad, "::: not yaml :::")
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including(
                                "code" => "schema.parse_error",
                                "level" => "error",
                                "subject" => bad,
                              ))
    expect(issues.first["fix"]).to include(bad)
  end
end
