require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Dependencies do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true }
        - key: derived.catalogs.people
          path: derived/catalogs/people.md
          zone: derived
          schema: null
          owner: build:auto
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

  after { FileUtils.remove_entry(tmp) }

  it "lists dependencies declared in projection.select" do
    expect(store.deps("derived.catalogs.people")).to eq(["working.people"])
  end

  it "lists reverse dependencies" do
    expect(store.rdeps("working.people")).to eq(["derived.catalogs.people"])
  end

  it "lists published entries with publish_to" do
    expect(store.published.map { |r| r["key"] }).to include("derived.catalogs.people")
    rec = store.published.find { |r| r["key"] == "derived.catalogs.people" }
    expect(rec["publish_to"]).to eq(["PEOPLE.md"])
  end

  it "returns empty deps for an unknown key" do
    expect(store.deps("does.not.exist")).to eq([])
  end
end
