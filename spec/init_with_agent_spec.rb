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

  it "writes .mcp.json at the project root and reports it" do
    dir, root, result = init(with_agent: true)
    mcp = File.join(File.dirname(root), ".mcp.json")
    expect(File.exist?(mcp)).to be true
    expect(File.read(mcp)).to include("\"textus\"").and include("mcp")
    expect(result["mcp_config"]).to eq("written")
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "never clobbers an existing .mcp.json" do
    dir = Dir.mktmpdir
    File.write(File.join(dir, ".mcp.json"), "{\"keep\":true}\n")
    root = File.join(dir, ".textus")
    result = Textus::Init.run(root, with_agent: true)
    expect(File.read(File.join(dir, ".mcp.json"))).to eq("{\"keep\":true}\n")
    expect(result["mcp_config"]).to eq("skipped")
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "does not write .mcp.json in the default profile" do
    dir, root, result = init(with_agent: false)
    expect(File.exist?(File.join(File.dirname(root), ".mcp.json"))).to be false
    expect(result).not_to have_key("mcp_config")
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "drives the agent profile from the CLI --with-agent flag" do
    Dir.mktmpdir do |dir|
      out = StringIO.new
      verb = Textus::CLI::Verb::Init.new(stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: dir)
      verb.parse(["--with-agent"])
      exit_code = verb.call(nil)
      expect(exit_code).to eq(0)
      expect(File.exist?(File.join(dir, ".textus", "templates", "orientation.mustache"))).to be true
      expect(File.exist?(File.join(dir, ".mcp.json"))).to be true
      payload = JSON.parse(out.string)
      expect(payload["profile"]).to eq("agent")
    end
  end

  it "defaults to the neutral profile without the flag" do
    Dir.mktmpdir do |dir|
      out = StringIO.new
      verb = Textus::CLI::Verb::Init.new(stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: dir)
      verb.parse([])
      verb.call(nil)
      expect(File.exist?(File.join(dir, ".textus", "templates", "orientation.mustache"))).to be false
      expect(JSON.parse(out.string)["profile"]).to eq("default")
    end
  end
end
