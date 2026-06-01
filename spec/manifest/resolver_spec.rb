require "spec_helper"

RSpec.describe Textus::Manifest::Resolver do
  include_context "textus_store_fixture"

  let(:manifest) { Textus::Manifest.load(root) }
  let(:resolver) { described_class.new(manifest.data) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, owner: human:self, kind: leaf}

    YAML
  end

  it "resolves a leaf key to a Resolution" do
    res = resolver.resolve("working.notes")
    expect(res).to be_a(Textus::Manifest::Resolver::Resolution)
    expect(res.path).to end_with("/zones/working/notes.md")
  end

  it "raises UnknownKey for missing entries with suggestions" do
    expect { resolver.resolve("working.note") }.to raise_error(Textus::UnknownKey)
  end

  describe "ignore patterns" do
    include TextusSpecHelpers

    before do
      # `build` has legal key segments, so without `ignore:` it WOULD enumerate
      # as skills.alpha.build.generated — this proves exclusion is by the ignore
      # rule, not by incidental segment-illegality.
      store_from_manifest(
        root,
        zones: %w[knowledge],
        manifest: <<~YAML,
          version: textus/3
          zones:
            - { name: knowledge, kind: canon }
          entries:
            - key: skills
              path: knowledge/skills
              zone: knowledge
              owner: human:self
              kind: nested
              index_filename: SKILL.md
              ignore:
                - "**/build/**"
        YAML
        files: {
          "zones/knowledge/skills/alpha/SKILL.md" => "# alpha\n",
          "zones/knowledge/skills/alpha/build/generated/SKILL.md" => "# generated\n",
        },
      )
    end

    it "drops paths under an ignored subtree from enumeration" do
      keys = resolver.enumerate.map { |r| r[:key] }
      expect(keys).to include("skills.alpha")
      expect(keys).not_to include("skills.alpha.build.generated")
      expect(keys.none? { |k| k.include?("build") }).to be(true)
    end
  end
end
