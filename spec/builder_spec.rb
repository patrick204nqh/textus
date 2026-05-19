require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Builder do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
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

  it "materializes a derived entry and updates symlink" do
    res = Textus::Builder.new(store).build
    expect(res["built"].map { |b| b["key"] }).to include("derived.catalogs.people")
    body = File.read(File.join(root, "zones/derived/catalogs/people.md"))
    expect(body).to include("- alice (x)")
    expect(body).to include("- bob (y)")

    published = File.join(File.dirname(root), "PEOPLE.md")
    expect(File.symlink?(published) || File.exist?(published + ".textus-managed.json")).to be true
  end
end
