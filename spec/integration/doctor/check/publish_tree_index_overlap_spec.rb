require "spec_helper"

RSpec.describe Textus::Doctor::Check::PublishTreeIndexOverlap do
  include_context "textus_store_fixture"

  def write_manifest(entries_yaml)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
        - { name: gen, kind: machine }
      entries:
      #{entries_yaml}
    YAML
  end

  def issues
    container = Textus::Store.new(root).container
    described_class.new(container).call
  end

  it "warns when a publish_tree target overlaps a derived publish_to and the index is not ignored" do
    write_manifest(<<~Y)
      - key: working.skills
        kind: nested
        path: working/skills
        zone: working
        schema: null
        nested: true
        publish:
          - { tree: "skills" }
      - key: gen.skilldoc
        kind: produced
        path: gen/skilldoc.yaml
        zone: gen
        schema: null
        publish:
          - { to: "skills/my-skill/SKILL.md" }
        source: { from: project, select: ["working.skilldefs"] }
    Y

    found = issues
    expect(found.map { |i| i["code"] }).to include("publish.tree_index_overlap")
    expect(found.first["subject"]).to eq("working.skills")
  end

  it "is silent when the tree ignores the overlapping index filename" do
    write_manifest(<<~Y)
      - key: working.skills
        kind: nested
        path: working/skills
        zone: working
        schema: null
        nested: true
        publish:
          - { tree: "skills" }
        ignore: ["**/SKILL.md"]
      - key: gen.skilldoc
        kind: produced
        path: gen/skilldoc.yaml
        zone: gen
        schema: null
        publish:
          - { to: "skills/my-skill/SKILL.md" }
        source: { from: project, select: ["working.skilldefs"] }
    Y

    expect(issues).to be_empty
  end

  it "still warns when the ignore pattern is too shallow to match the real path" do
    write_manifest(<<~Y)
      - key: working.skills
        kind: nested
        path: working/skills
        zone: working
        schema: null
        nested: true
        publish:
          - { tree: "skills" }
        ignore: ["SKILL.md"]
      - key: gen.skilldoc
        kind: produced
        path: gen/skilldoc.yaml
        zone: gen
        schema: null
        publish:
          - { to: "skills/my-skill/SKILL.md" }
        source: { from: project, select: ["working.skilldefs"] }
    Y

    expect(issues.map { |i| i["code"] }).to include("publish.tree_index_overlap")
  end

  it "is silent when no derived publish_to falls under any publish_tree target" do
    write_manifest(<<~Y)
      - key: working.skills
        kind: nested
        path: working/skills
        zone: working
        schema: null
        nested: true
        publish:
          - { tree: "skills" }
      - key: gen.other
        kind: produced
        path: gen/other.yaml
        zone: gen
        schema: null
        publish:
          - { to: "docs/other.md" }
        source: { from: project, select: ["working.skilldefs"] }
    Y

    expect(issues).to be_empty
  end
end
