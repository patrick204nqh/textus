require "spec_helper"

RSpec.describe Textus::Doctor::Check::IllegalKeys do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  def issues_for(manifest:, files:)
    store = store_from_manifest(root, zones: %w[knowledge], manifest: manifest, files: files)
    described_class.new(store.container).call
  end

  context "with a nested entry and an ignore pattern" do
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
            ignore:
              - "**/dist/**"
      YAML
    end

    it "does not flag illegal segments inside an ignored subtree" do
      issues = issues_for(
        manifest: manifest,
        files: {
          "data/knowledge/notes/ok.md" => "# ok\n",
          "data/knowledge/notes/dist/Build_Junk.md" => "# generated\n",
        },
      )
      subjects = issues.map { |i| i["subject"] }
      expect(subjects.any? { |s| s.include?("dist") }).to be(false)
    end

    it "still flags a genuinely illegal in-scope segment" do
      issues = issues_for(
        manifest: manifest,
        files: { "data/knowledge/notes/Bad_Dir/note.md" => "# nope\n" },
      )
      expect(issues).to include(hash_including("code" => "key.illegal"))
    end
  end
end
