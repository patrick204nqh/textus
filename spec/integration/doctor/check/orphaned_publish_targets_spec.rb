require "spec_helper"

RSpec.describe Textus::Doctor::Check::OrphanedPublishTargets do
  include_context "textus_store_fixture"

  def write_manifest
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - key: knowledge.skills
          kind: nested
          path: data/knowledge/skills
          lane: knowledge
          schema: null
          nested: true
          publish:
            - { tree: "skills" }
    YAML
  end

  def write_file(rel, contents)
    abs = File.join(root, "data/knowledge", rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, contents)
  end

  it "flags a published target whose source leaf was removed" do
    write_manifest
    write_file("skills/my-skill/SKILL.md", "---\nname: my-skill\n---\nbody\n")
    store = Textus::Store.new(root)
    converge_now(store)

    # Whole-leaf removal: delete the source dir; per-entry build won't revisit it.
    FileUtils.rm_rf(File.join(root, "data/knowledge/skills/my-skill"))

    issues = described_class.new(store.container).call
    subjects = issues.map { |i| i["subject"] }
    expect(subjects.any? { |s| s.end_with?("skills/my-skill/SKILL.md") }).to be true
    expect(issues.first["code"]).to eq("publish.orphaned_target")
  end

  it "reports nothing when every source is present" do
    write_manifest
    write_file("skills/my-skill/SKILL.md", "---\nname: my-skill\n---\nbody\n")
    store = Textus::Store.new(root)
    converge_now(store)

    expect(described_class.new(store.container).call).to eq([])
  end
end
