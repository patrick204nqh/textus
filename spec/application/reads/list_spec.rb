require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Reads::List do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "zones", "notes"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
        - { name: notes,   write_policy: [human] }
      entries:
        - { key: working.alpha, path: working/alpha.md, zone: working }
        - { key: working.beta,  path: working/beta.md,  zone: working }
        - { key: notes.report,  path: notes/report.md,  zone: notes }
    YAML
    File.write(File.join(textus, "zones", "working", "alpha.md"), "---\nname: alpha\n---\nbody\n")
    File.write(File.join(textus, "zones", "working", "beta.md"),  "---\nname: beta\n---\nbody\n")
    File.write(File.join(textus, "zones", "notes",   "report.md"), "---\nname: report\n---\nbody\n")
    Textus::Store.new(textus)
  end

  it "returns all entries when called with no filters" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = Textus::Operations.for(store, role: "human")
      rows = ops.reads.list.call
      expect(rows.map { |r| r["key"] }).to contain_exactly(
        "working.alpha", "working.beta", "notes.report"
      )
    end
  end

  it "filters by prefix" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = Textus::Operations.for(store, role: "human")
      rows = ops.reads.list.call(prefix: "working")
      expect(rows.map { |r| r["key"] }).to contain_exactly("working.alpha", "working.beta")
    end
  end

  it "filters by zone" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = Textus::Operations.for(store, role: "human")
      rows = ops.reads.list.call(zone: "notes")
      expect(rows.map { |r| r["key"] }).to eq(["notes.report"])
    end
  end
end
