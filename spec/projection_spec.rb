require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Projection do
  let(:tmp)  { Dir.mktmpdir("textus-proj") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: working, writable_by: [human, ai, script] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true }
    YAML
    File.write(File.join(root, "zones/working/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/working/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
  end
  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "selects + plucks + sorts" do
    proj = Textus::Projection.new(store, {
      "select" => "working.people",
      "pluck"  => ["name", "org"],
      "sort_by" => "name",
    })
    result = proj.run
    expect(result["entries"].length).to eq(2)
    expect(result["entries"].first).to eq("name" => "alice", "org" => "x")
  end

  it "caps at limit=1000 by default" do
    proj = Textus::Projection.new(store, { "select" => "working.people" })
    expect(proj.run["entries"].length).to be <= 1000
  end

  it "raises if limit > 1000" do
    expect {
      Textus::Projection.new(store, { "select" => "working.people", "limit" => 5000 })
    }.to raise_error(Textus::InvalidProjection)
  end
end
