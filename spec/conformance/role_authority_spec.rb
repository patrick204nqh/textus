require "spec_helper"

RSpec.describe "Role authority via schema.maintained_by" do
  let(:tmp)   { Dir.mktmpdir("textus-role-authority") }
  let(:root)  { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "data/proposals/people"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: proposals, kind: queue }
      entries:
        - { key: proposals.people, path: proposals/people, zone: proposals, schema: person, owner: human:patrick, kind: nested}

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
    store.as("agent").put(
      "proposals.people.alice",
      meta: { "name" => "alice", "full_name" => "Alice Wonder", "embedding" => [0.1, 0.2] },
      body: "",
    )
    res = store.as(Textus::Role::DEFAULT).validate_all
    codes = res["violations"].map { |v| v["code"] }
    expect(codes).to include("role_authority")
    bad = res["violations"].find { |v| v["code"] == "role_authority" }
    expect(bad["field"]).to eq("full_name")
    expect(bad["expected"]).to eq("human")
    expect(bad["last_writer"]).to eq("agent")
  end

  it "allows human to override ai-owned fields" do
    store.as("human").put(
      "proposals.people.bob",
      meta: { "name" => "bob", "full_name" => "Bob Builder", "embedding" => [0.3] },
      body: "",
    )
    res = store.as(Textus::Role::DEFAULT).validate_all
    expect(res["violations"]).to be_empty
  end

  context "with a non-default capability assignment" do
    let(:tmp)   { Dir.mktmpdir("textus-role-authority-renamed") }
    let(:root)  { File.join(tmp, ".textus") }
    let(:store) { Textus::Store.new(root) }

    before do
      FileUtils.mkdir_p(File.join(root, "schemas"))
      FileUtils.mkdir_p(File.join(root, "data/proposals/people"))

      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
          - { name: agent, can: [propose] }
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.people, path: knowledge/people, zone: knowledge, schema: person, owner: human:patrick, kind: nested}

      YAML

      File.write(File.join(root, "schemas/person.yaml"), <<~YAML)
        name: person
        required: [full_name]
        fields:
          full_name:  { type: string, maintained_by: agent }
          embedding:  { type: array,  maintained_by: agent }
      YAML
    end

    it "allows the author role to override agent-owned fields" do
      store.as("human").put(
        "knowledge.people.carol",
        meta: { "name" => "carol", "full_name" => "Carol Override", "embedding" => [0.5] },
        body: "",
      )
      res = store.as(Textus::Role::DEFAULT).validate_all
      authority = res["violations"].select { |v| v["code"] == "role_authority" }
      expect(authority).to be_empty
    end
  end
end
