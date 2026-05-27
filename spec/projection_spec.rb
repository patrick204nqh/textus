require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Application::Projection do
  let(:tmp)  { Dir.mktmpdir("textus-proj") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  def build_projection(spec)
    ops = Textus::Operations.for(store)
    Textus::Application::Projection.new(
      reader: ops.method(:get),
      spec: spec,
      lister: ops.method(:list),
      transform_resolver: ->(name) { store.bus.rpc_callable(:transform_rows, name) },
      transform_context: store,
    )
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true, kind: nested}

    YAML
    File.write(File.join(root, "zones/working/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/working/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "selects + plucks + sorts" do
    proj = build_projection(
      "select" => "working.people",
      "pluck" => %w[name org],
      "sort_by" => "name",
    )
    result = proj.run
    expect(result["entries"].length).to eq(2)
    expect(result["entries"].first).to include("name" => "alice", "org" => "x")
    expect(result["entries"].first).to include("_first" => true, "_last" => false, "_index" => 0)
    expect(result["entries"].last).to include("_first" => false, "_last" => true)
  end

  it "caps at limit=1000 by default" do
    proj = build_projection("select" => "working.people")
    expect(proj.run["entries"].length).to be <= 1000
  end

  it "raises if limit > 1000" do
    expect do
      build_projection("select" => "working.people", "limit" => 5000)
    end.to raise_error(Textus::InvalidProjection)
  end

  it "applies a reducer before sort/limit" do
    store.bus.register(:transform_rows, :score) do |store:, rows:, config:|
      _ = config
      _ = store
      rows.map { |r| r.merge("score" => r["name"].length) }
    end
    proj = build_projection(
      "select" => "working.people",
      "pluck" => ["name"],
      "transform" => "score",
      "sort_by" => "score",
    )
    out = proj.run
    expect(out["entries"].map { |r| r["score"] }).to eq([3, 5])
  end

  it "raises UsageError when a reducer exceeds 2s timeout" do
    store.bus.register(:transform_rows, :slow) do |store:, rows:, config:|
      _ = rows
      _ = config
      _ = store
      sleep 5
    end
    proj = build_projection(
      "select" => "working.people",
      "transform" => "slow",
    )
    expect { proj.run }.to raise_error(Textus::UsageError, /transform_rows 'slow' exceeded 2s timeout/)
  end
end
