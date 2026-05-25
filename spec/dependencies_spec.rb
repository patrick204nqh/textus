require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Dependencies do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: output, write_policy: [builder] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true }
        - key: output.catalogs.people
          path: output/catalogs/people.md
          zone: output
          schema: null
          owner: builder:auto
          projection: { select: working.people, pluck: [name, org], sort_by: name }
          template: people.mustache
          publish_to: [PEOPLE.md]
    YAML

    File.write(File.join(root, "zones/working/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/working/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
  end

  it "lists dependencies declared in projection.select" do
    expect(store.deps("output.catalogs.people")).to eq(["working.people"])
  end

  it "lists reverse dependencies" do
    expect(store.rdeps("working.people")).to eq(["output.catalogs.people"])
  end

  it "lists published entries with publish_to" do
    expect(store.published.map { |r| r["key"] }).to include("output.catalogs.people")
    rec = store.published.find { |r| r["key"] == "output.catalogs.people" }
    expect(rec["publish_to"]).to eq(["PEOPLE.md"])
  end

  it "returns empty deps for an unknown key" do
    expect(store.deps("does.not.exist")).to eq([])
  end
end
