require "spec_helper"

RSpec.describe Textus::Projection do
  let(:tmp)  { Dir.mktmpdir("textus-proj") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  def build_projection(spec)
    ops = store.as(Textus::Role::DEFAULT)
    Textus::Projection.new(
      reader: ops.method(:get),
      spec: spec,
      lister: ops.method(:list),
      rpc: store.rpc,
      transform_context: store,
    )
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.people, path: working/people, zone: working, owner: human:self, kind: nested}

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
    store.rpc.register(:transform_rows, :score) do |caps:, rows:, config:|
      _ = config
      _ = caps
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
    store.rpc.register(:transform_rows, :slow) do |caps:, rows:, config:|
      _ = rows
      _ = config
      _ = caps
      sleep 5
    end
    proj = build_projection(
      "select" => "working.people",
      "transform" => "slow",
    )
    expect { proj.run }.to raise_error(Textus::UsageError, /transform_rows 'slow' exceeded 2s timeout/)
  end
end
