require "spec_helper"

RSpec.describe "publish_tree (ADR 0047)" do
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

  def write_file(rel, contents)
    abs = File.join(root, "zones/working", rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, contents)
  end

  describe "manifest wiring" do
    it "exposes publish_tree on the loaded nested entry" do
      write_manifest(<<~Y)
        - key: working.skills
          kind: nested
          path: working/skills
          zone: working
          schema: null
          nested: true
          publish_tree: "skills"
      Y

      m = Textus::Manifest.load(root)
      entry = m.data.entries.find { |e| e.key == "working.skills" }
      expect(entry.publish_tree).to eq("skills")
    end
  end
end
