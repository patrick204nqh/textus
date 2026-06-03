require "spec_helper"

# ADR 0047 — publish_tree mirrors opaque payload by path; its files are never
# addressable keys. Regression guard: neither doctor's IllegalKeys nor the
# resolver may key-walk them, so a publish_tree subtree carrying non-key-legal
# filenames (uppercase SKILL.md, README) must stay doctor-green and still
# mirror. The Publisher always honored opacity; these two paths did not until
# the `Publish::Mode#keyless?` guard.
RSpec.describe "publish_tree opacity (ADR 0047)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:manifest) do
    <<~YAML
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - key: working.published
          path: working/skills
          zone: working
          owner: human:self
          kind: nested
          nested: true
          publish:
            tree: "skills"
    YAML
  end

  let(:files) do
    {
      "zones/working/skills/my-skill/SKILL.md" => "# my skill\n",
      "zones/working/skills/my-skill/README.md" => "# readme\n",
      "zones/working/skills/my-skill/references/algo.md" => "notes\n",
    }
  end

  let(:store) { store_from_manifest(root, zones: %w[working], manifest: manifest, files: files) }

  it "does not flag uppercase filenames under a publish_tree entry (doctor green)" do
    issues = Textus::Doctor::Check::IllegalKeys.new(store.container).call
    expect(issues).to be_empty
  end

  it "does not enumerate publish_tree files as keys" do
    keys = store.container.manifest.resolver.enumerate.map { |r| r[:key] }
    expect(keys).to be_empty
  end

  it "still mirrors the whole subtree, uppercase files included" do
    repo_root = File.dirname(root)
    store.as("automation").build

    expect(File.read(File.join(repo_root, "skills/my-skill/SKILL.md"))).to eq("# my skill\n")
    expect(File.read(File.join(repo_root, "skills/my-skill/README.md"))).to eq("# readme\n")
    expect(File.read(File.join(repo_root, "skills/my-skill/references/algo.md"))).to eq("notes\n")
  end

  it "still flags illegal segments on a non-publish nested entry (guard not over-broad)" do
    plain = <<~YAML
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - key: working.notes
          path: working/notes
          zone: working
          owner: human:self
          kind: nested
          nested: true
    YAML
    plain_store = store_from_manifest(
      root, zones: %w[working], manifest: plain,
            files: { "zones/working/notes/Bad_Dir/note.md" => "x\n" }
    )
    issues = Textus::Doctor::Check::IllegalKeys.new(plain_store.container).call
    expect(issues).to include(hash_including("code" => "key.illegal"))
  end
end
