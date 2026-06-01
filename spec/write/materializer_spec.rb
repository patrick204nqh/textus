require "spec_helper"

RSpec.describe Textus::Write::Materializer do
  subject(:materializer) do
    container = store.container
    Textus::Write::Materializer.new(
      container: container,
      call: ctx,
    )
  end

  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }
  let(:ctx)   { test_ctx(role: "automation") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/people"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: derived }
      entries:
        - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested }

        - key: artifacts.catalogs.people
          kind: derived
          path: artifacts/catalogs/people.md
          zone: artifacts
          owner: automation:auto
          compute: { kind: projection, select: knowledge.people, pluck: [name, org], sort_by: name }
          template: people.mustache
    YAML

    File.write(File.join(root, "zones/knowledge/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/knowledge/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
  end

  it "materializes a Derived entry and writes rendered content to disk" do
    mentry = store.manifest.data.entries.find { |e| e.key == "artifacts.catalogs.people" }
    expect(mentry).to be_a(Textus::Manifest::Entry::Derived)

    target_path = materializer.run(mentry)

    expect(File.exist?(target_path)).to be true
    content = File.read(target_path)
    expect(content).to include("- alice (x)")
    expect(content).to include("- bob (y)")
  end
end
