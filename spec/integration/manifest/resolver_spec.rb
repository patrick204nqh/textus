require "spec_helper"

RSpec.describe Textus::Manifest::Resolver do
  include_context "textus_store_fixture"

  let(:manifest) { Textus::Manifest.load(root) }
  let(:resolver) { described_class.new(manifest.data) }

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.notes, path: knowledge/notes.md, lane: knowledge, owner: human:self, kind: leaf}

    YAML
  end

  it "resolves a leaf key to a Resolution" do
    res = resolver.resolve("knowledge.notes")
    expect(res).to be_a(Textus::Manifest::Resolver::Resolution)
    expect(res.path).to end_with("/data/knowledge/notes.md")
  end

  it "raises UnknownKey for missing entries with suggestions" do
    expect { resolver.resolve("knowledge.note") }.to raise_error(Textus::UnknownKey)
  end

  describe "ignore patterns" do
    include TextusSpecHelpers

    before do
      # `build` has legal key segments, so without `ignore:` it WOULD enumerate
      # as skills.alpha.build.generated — this proves exclusion is by the ignore
      # rule, not by incidental segment-illegality.
      store_from_manifest(
        root,
        lanes: %w[knowledge],
        manifest: <<~YAML,
          version: textus/3
          lanes:
            - { name: knowledge, kind: canon }
          entries:
            - key: skills
              path: knowledge/skills
              lane: knowledge
              owner: human:self
              kind: nested
              ignore:
                - "**/build/**"
        YAML
        files: {
          "data/knowledge/skills/alpha/intro.md" => "# alpha\n",
          "data/knowledge/skills/alpha/build/generated.md" => "# generated\n",
        },
      )
    end

    it "drops paths under an ignored subtree from enumeration" do
      keys = resolver.enumerate.map { |r| r[:key] }
      expect(keys).to include("skills.alpha.intro")
      expect(keys).not_to include("skills.alpha.build.generated")
      expect(keys.none? { |k| k.include?("build") }).to be(true)
    end
  end

  describe "include_keyless (ADR 0047 / ADR 0097)" do
    include TextusSpecHelpers

    before do
      # A publish_tree nested entry is keyless: its files are never enumerated
      # as addressable keys on the public surface (ADR 0047). ADR 0097's ADR-log
      # projection needs to read those files as *source* data, which the
      # include_keyless: override permits without exposing them to `list`.
      store_from_manifest(
        root,
        lanes: %w[knowledge],
        manifest: <<~YAML,
          version: textus/3
          lanes:
            - { name: knowledge, kind: canon }
          entries:
            - key: decisions
              path: knowledge/decisions
              lane: knowledge
              owner: human:self
              kind: nested
              publish:
                - { tree: docs/decisions }
        YAML
        files: {
          "data/knowledge/decisions/0001-first.md" => "# ADR 0001 — First\n",
        },
      )
    end

    it "excludes keyless publish_tree files by default (public surface)" do
      keys = resolver.enumerate.map { |r| r[:key] }
      expect(keys.none? { |k| k.start_with?("decisions") }).to be(true)
    end

    it "includes keyless publish_tree files when include_keyless: true" do
      keys = resolver.enumerate(include_keyless: true).map { |r| r[:key] }
      expect(keys).to include("decisions.0001-first")
    end
  end
end
