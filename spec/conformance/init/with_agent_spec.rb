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

  it "appends the orientation entries under --with-agent" do
    dir, root, = init(with_agent: true)
    manifest = File.read(File.join(root, "manifest.yaml"))
    expect(manifest).to include("key: artifacts.derived.orientation")
    expect(manifest).to include("to: CLAUDE.md").and include("to: AGENTS.md")
    # base entries still present (additive superset)
    expect(manifest).to include("key: knowledge.identity")
    expect(manifest).to include("key: knowledge.project")
    # entries stay above the rules block
    expect(manifest.index("artifacts.derived.orientation")).to be < manifest.index("rules:")
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "produces a loadable manifest under --with-agent" do
    dir, root, = init(with_agent: true)
    expect { Textus::Manifest.load(root) }.not_to raise_error
    entry = Textus::Manifest.load(root).data.entries.find { |e| e.key == "artifacts.derived.orientation" }
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

  it "scaffolds the orientation template under --with-agent" do
    dir, root, = init(with_agent: true)
    expect(File.read(File.join(root, "templates", "orientation.erb"))).to include('project["name"]')
    expect(File.exist?(File.join(root, "workflows"))).to be true
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  it "writes .mcp.json at the project root and reports it" do
    dir, root, result = init(with_agent: true)
    mcp = File.join(File.dirname(root), ".mcp.json")
    expect(File.exist?(mcp)).to be true
    config = JSON.parse(File.read(mcp))
    expect(config.dig("mcpServers", "textus", "command")).to eq("textus")
    expect(config.dig("mcpServers", "textus", "args")).to include("serve")
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
      verb = Textus::Surface::CLI::Verb::Init.new(stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: dir)
      verb.parse(["--with-agent"])
      exit_code = verb.call(nil)
      expect(exit_code).to eq(0)
      expect(File.exist?(File.join(dir, ".textus", "templates", "orientation.erb"))).to be true
      expect(File.exist?(File.join(dir, ".mcp.json"))).to be true
      payload = JSON.parse(out.string)
      expect(payload["profile"]).to eq("agent")
    end
  end

  it "defaults to the neutral profile without the flag" do
    Dir.mktmpdir do |dir|
      out = StringIO.new
      verb = Textus::Surface::CLI::Verb::Init.new(stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: dir)
      verb.parse([])
      verb.call(nil)
      expect(File.exist?(File.join(dir, ".textus", "templates", "orientation.erb"))).to be false
      expect(JSON.parse(out.string)["profile"]).to eq("default")
    end
  end

  describe "agent-memory promise (ADR 0033)" do
    it "lets the agent write its scratchpad without a human accept" do
      Dir.mktmpdir do |dir|
        dot = File.join(dir, ".textus")
        Textus::Init.run(dot)
        store = Textus::Store.new(dot)
        store.with_role("agent").entry(:put, "scratchpad.notes.s1", meta: { "name" => "s1" }, body: "remembered\n")
        expect(store.with_role("agent").entry(:get, "scratchpad.notes.s1").body).to eq("remembered\n")
      end
    end
  end

  describe "buildable orientation" do
    it "drain does not raise when no orientation workflow is registered" do
      Dir.mktmpdir do |dir|
        root = File.join(dir, ".textus")
        Textus::Init.run(root, with_agent: true)

        store = Textus::Store.new(root)
        store.with_role("human").entry(:put,
                                       "knowledge.project",
                                       meta: { "name" => "project", "description" => "double-entry accounting service" },
                                       body: "")
        expect { store.with_role("automation").ops(:drain) }.not_to raise_error
      end
    end
  end
end
