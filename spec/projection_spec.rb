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
      version: textus/2
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
                                    "pluck" => %w[name org],
                                    "sort_by" => "name",
                                  })
    result = proj.run
    expect(result["entries"].length).to eq(2)
    expect(result["entries"].first).to include("name" => "alice", "org" => "x")
    expect(result["entries"].first).to include("_first" => true, "_last" => false, "_index" => 0)
    expect(result["entries"].last).to include("_first" => false, "_last" => true)
  end

  it "caps at limit=1000 by default" do
    proj = Textus::Projection.new(store, { "select" => "working.people" })
    expect(proj.run["entries"].length).to be <= 1000
  end

  it "raises if limit > 1000" do
    expect do
      Textus::Projection.new(store, { "select" => "working.people", "limit" => 5000 })
    end.to raise_error(Textus::InvalidProjection)
  end

  it "applies a reducer before sort/limit" do
    store.registry.register(:reduce, :score) do |store:, rows:, config:|
      _ = config
      _ = store
      rows.map { |r| r.merge("score" => r["name"].length) }
    end
    proj = Textus::Projection.new(store, {
                                    "select" => "working.people",
                                    "pluck" => ["name"],
                                    "reducer" => "score",
                                    "sort_by" => "score",
                                  })
    out = proj.run
    expect(out["entries"].map { |r| r["score"] }).to eq([3, 5])
  end

  it "raises UsageError when a reducer exceeds 2s timeout" do
    store.registry.register(:reduce, :slow) do |store:, rows:, config:|
      _ = rows
      _ = config
      _ = store
      sleep 5
    end
    proj = Textus::Projection.new(store, {
                                    "select" => "working.people",
                                    "reducer" => "slow",
                                  })
    expect { proj.run }.to raise_error(Textus::UsageError, /reducer 'slow' exceeded 2s timeout/)
  end
end
