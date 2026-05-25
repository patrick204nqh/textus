require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Role authority via schema.maintained_by" do
  let(:tmp)   { Dir.mktmpdir("textus-role-authority") }
  let(:root)  { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, writable_by: [human, ai, script] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: person, owner: human:patrick, nested: true }
    YAML

    File.write(File.join(root, "schemas/person.yaml"), <<~YAML)
      name: person
      required: [full_name]
      fields:
        full_name:  { type: string, maintained_by: human }
        embedding:  { type: array,  maintained_by: ai }
    YAML
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "flags fields written by the wrong role" do
    store.put("working.people.alice",
              meta: { "name" => "alice", "full_name" => "Alice Wonder", "embedding" => [0.1, 0.2] },
              body: "", as: "ai")
    res = store.validate_all
    codes = res["violations"].map { |v| v["code"] }
    expect(codes).to include("role_authority")
    bad = res["violations"].find { |v| v["code"] == "role_authority" }
    expect(bad["field"]).to eq("full_name")
    expect(bad["expected"]).to eq("human")
    expect(bad["last_writer"]).to eq("ai")
  end

  it "allows human to override ai-owned fields" do
    store.put("working.people.bob",
              meta: { "name" => "bob", "full_name" => "Bob Builder", "embedding" => [0.3] },
              body: "", as: "human")
    res = store.validate_all
    expect(res["violations"]).to be_empty
  end
end
