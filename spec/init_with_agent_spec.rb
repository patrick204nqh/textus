# spec/init_with_agent_spec.rb
require "spec_helper"

RSpec.describe "Textus::Init with_agent profile" do
  def init(with_agent:)
    dir = Dir.mktmpdir
    root = File.join(dir, ".textus")
    result = Textus::Init.run(root, with_agent: with_agent)
    [dir, root, result]
  end

  it "leaves the default manifest byte-identical when with_agent is false" do
    dir, root, = init(with_agent: false)
    expect(File.read(File.join(root, "manifest.yaml"))).to eq(Textus::Init::DEFAULT_MANIFEST)
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "appends the orientation projection entries under --with-agent" do
    dir, root, = init(with_agent: true)
    manifest = File.read(File.join(root, "manifest.yaml"))
    expect(manifest).to include("key: artifacts.orientation")
    expect(manifest).to include("transform: orientation_reducer")
    expect(manifest).to include("- CLAUDE.md").and include("- AGENTS.md")
    # base entries still present (additive superset)
    expect(manifest).to include("key: knowledge.identity")
    expect(manifest).to include("key: knowledge.project")
    # entries stay above the rules block
    expect(manifest.index("artifacts.orientation")).to be < manifest.index("rules:")
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "produces a loadable manifest under --with-agent" do
    dir, root, = init(with_agent: true)
    expect { Textus::Manifest.load(root) }.not_to raise_error
    entry = Textus::Manifest.load(root).data.entries.find { |e| e.key == "artifacts.orientation" }
    expect(entry).not_to be_nil
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "scaffolds project + runbook schemas only under --with-agent" do
    dir, root, = init(with_agent: true)
    expect(File.read(File.join(root, "schemas", "project.yaml"))).to include("name:")
    expect(File.exist?(File.join(root, "schemas", "runbook.yaml"))).to be true
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "does NOT scaffold those schemas in the default profile" do
    dir, root, = init(with_agent: false)
    expect(File.exist?(File.join(root, "schemas", "project.yaml"))).to be false
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "scaffolds the orientation template + reducer hook under --with-agent" do
    dir, root, = init(with_agent: true)
    expect(File.read(File.join(root, "templates", "orientation.mustache"))).to include("{{project.name}}")
    expect(File.read(File.join(root, "hooks", "orientation_reducer.rb"))).to include(":transform_rows, :orientation_reducer")
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end
