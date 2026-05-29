require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Read::SchemaEnvelope do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "schemas"))
    File.write(File.join(textus, "schemas", "person.yaml"), <<~YAML)
      name: person
      fields:
        full_name: { type: string, maintained_by: human }
    YAML
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: origin, write_policy: [human, runner] }
      entries:
        - { key: working.person, path: working/person.md, zone: working, schema: person, kind: leaf}

    YAML
    File.write(File.join(textus, "zones", "working", "person.md"), "---\nfull_name: Alice\n---\nbody\n")
    Textus::Store.new(textus)
  end

  it "returns a hash with key, schema_ref, and schema as a Hash for a declared schema" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      result = ops.schema_envelope("working.person")

      expect(result).to include(
        "key" => "working.person",
        "schema_ref" => "person",
        "schema" => be_a(Hash),
      )
      expect(result["schema"]).to include("name" => "person")
    end
  end
end
