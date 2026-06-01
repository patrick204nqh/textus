require "spec_helper"

RSpec.describe "publish_each directory leaves (ADR 0046)" do
  include_context "textus_store_fixture"

  def write_manifest(entries_yaml)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
      #{entries_yaml}
    YAML
  end

  def skills_entry(extra = "")
    <<~Y
      - key: working.skills
        kind: nested
        path: working/skills
        zone: working
        schema: null
        nested: true
        index_filename: SKILL.md
        publish_each: "skills/{leaf}"
      #{extra}
    Y
  end

  def write_file(rel, contents)
    abs = File.join(root, "zones/working", rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, contents)
  end

  describe "enumeration: shallowest index wins" do
    it "treats a SKILL.md inside a leaf's subtree as payload, not a second leaf" do
      write_manifest(skills_entry)
      write_file("skills/my-skill/SKILL.md", "---\nname: my-skill\n---\nbody\n")
      write_file("skills/my-skill/references/SKILL.md", "nested index, not a leaf\n")

      m = Textus::Manifest.load(root)
      keys = m.resolver.enumerate(prefix: "working.skills").map { |r| r[:key] }
      expect(keys).to contain_exactly("working.skills.my-skill")
    end
  end
end
