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
      steps: store.steps,
      transform_context: store,
    )
  end

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge/people"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.people, path: data/knowledge/people, lane: knowledge, owner: human:self, kind: nested}

    YAML
    File.write(File.join(root, "data/knowledge/people/alice.md"),
               "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "data/knowledge/people/bob.md"),
               "---\nname: bob\norg: y\n---\n")
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "selects + plucks + sorts" do
    proj = build_projection(
      "select" => "knowledge.people",
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
    proj = build_projection("select" => "knowledge.people")
    expect(proj.run["entries"].length).to be <= 1000
  end

  it "raises if limit > 1000" do
    expect do
      build_projection("select" => "knowledge.people", "limit" => 5000)
    end.to raise_error(Textus::InvalidProjection)
  end

  it "applies a reducer before sort/limit" do
    klass = Class.new(Textus::Step::Transform) do
      define_method(:call) do |caps:, rows:, config:|
        _ = config
        _ = caps
        rows.map { |r| r.merge("score" => r["name"].length) }
      end
    end
    store.steps.register(klass.new.tap { |s| s.name = :score })
    proj = build_projection(
      "select" => "knowledge.people",
      "pluck" => ["name"],
      "transform" => "score",
      "sort_by" => "score",
    )

    out = proj.run
    expect(out["entries"].map { |r| r["score"] }).to eq([3, 5])
  end

  it "includes body in rows when 'body' is in the pluck list" do
    FileUtils.mkdir_p(File.join(root, "data/knowledge/docs"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.docs, path: data/knowledge/docs, lane: knowledge, owner: human:self, kind: nested, schema: null}
    YAML
    File.write(File.join(root, "data/knowledge/docs/readme.md"),
               "# Hello World\n\nSome content here.\n")
    proj = build_projection(
      "select" => "knowledge.docs",
      "pluck" => ["body"],
    )
    result = proj.run
    expect(result["entries"].length).to eq(1)
    expect(result["entries"].first["body"]).to include("# Hello World")
  end

  it "raises UsageError when a reducer exceeds 2s timeout" do
    klass = Class.new(Textus::Step::Transform) do
      define_method(:call) do |caps:, rows:, config:|
        _ = rows
        _ = config
        _ = caps
        sleep 5
      end
    end
    store.steps.register(klass.new.tap { |s| s.name = :slow })
    proj = build_projection(
      "select" => "knowledge.people",
      "transform" => "slow",
    )

    expect { proj.run }.to raise_error(Textus::UsageError, /transform 'slow' exceeded 2s timeout/)
  end
end
