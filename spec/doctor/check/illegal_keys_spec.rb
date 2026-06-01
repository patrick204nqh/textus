require "spec_helper"

RSpec.describe Textus::Doctor::Check::IllegalKeys do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  def issues_for(manifest:, files:)
    store = store_from_manifest(root, zones: %w[knowledge], manifest: manifest, files: files)
    described_class.new(store.container).call
  end

  context "index_filename entry with an ignore pattern" do
    let(:manifest) do
      <<~YAML
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - key: skills
            path: knowledge/skills
            zone: knowledge
            owner: human:self
            kind: nested
            nested: true
            index_filename: SKILL.md
            ignore:
              - "**/node_modules/**"
      YAML
    end

    it "does not flag illegal segments inside an ignored subtree" do
      issues = issues_for(
        manifest: manifest,
        files: {
          "zones/knowledge/skills/alpha/SKILL.md" => "# ok\n",
          "zones/knowledge/skills/alpha/node_modules/dep/SKILL.md" => "# vendored\n",
        },
      )
      subjects = issues.map { |i| i["subject"] }
      expect(subjects.any? { |s| s.include?("node_modules") }).to be(false)
    end

    it "still flags a genuinely illegal in-scope segment" do
      issues = issues_for(
        manifest: manifest,
        files: { "zones/knowledge/skills/Bad_Dir/SKILL.md" => "# nope\n" },
      )
      expect(issues).to include(hash_including("code" => "key.illegal"))
    end
  end

  context "bare nested entry (no index_filename) with an ignore pattern" do
    let(:manifest) do
      <<~YAML
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - key: notes
            path: knowledge/notes
            zone: knowledge
            owner: human:self
            kind: nested
            nested: true
            ignore:
              - "**/dist/**"
      YAML
    end

    it "does not flag illegal segments inside an ignored subtree" do
      issues = issues_for(
        manifest: manifest,
        files: {
          "zones/knowledge/notes/ok.md" => "# ok\n",
          "zones/knowledge/notes/dist/Build_Junk.md" => "# generated\n",
        },
      )
      subjects = issues.map { |i| i["subject"] }
      expect(subjects.any? { |s| s.include?("dist") }).to be(false)
    end
  end
end
