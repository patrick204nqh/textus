require "spec_helper"

RSpec.describe Textus::Produce::Acquire::Projection do
  subject(:data_builder) do
    container = store.container
    Textus::Produce::Acquire::Projection.new(
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

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested }

        - key: artifacts.catalogs.people
          kind: produced
          path: artifacts/catalogs/people.json
          zone: artifacts
          owner: automation:auto
          source: { from: project, select: [knowledge.people], pluck: [name, org], sort_by: name }
    YAML

    File.write(File.join(root, "zones/knowledge/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/knowledge/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
  end

  it "builds a produced (derived) entry and writes data (json) to disk" do
    mentry = store.manifest.data.entries.find { |e| e.key == "artifacts.catalogs.people" }
    expect(mentry).to be_a(Textus::Manifest::Entry::Produced)
    expect(mentry.derived?).to be(true)

    target_path = data_builder.run(mentry)

    expect(File.exist?(target_path)).to be true
    content = File.read(target_path)
    expect { JSON.parse(content) }.not_to raise_error
    expect(content).to include("alice")
    expect(content).to include("bob")
  end
end
