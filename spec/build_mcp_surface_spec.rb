require "spec_helper"

RSpec.describe "build is reachable from MCP" do
  it "declares the :mcp surface" do
    expect(Textus::Write::Build.contract.surfaces).to include(:mcp)
    expect(Textus::Write::Build.contract.mcp?).to be true
  end

  it "runs even when triggered by a non-build role (self-elevates, like an MCP agent)" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root, with_agent: true)
      store = Textus::Store.new(root)
      store.as("human").put("knowledge.project",
                            meta: { "name" => "project", "description" => "test project" }, body: "")

      # "agent" holds only :propose, never :build — yet build succeeds.
      expect { store.as("agent").build }.not_to raise_error
      expect(File.exist?(File.join(dir, "CLAUDE.md"))).to be true
    end
  end

  it "serializes builds via the shared lock (second concurrent build raises)" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root, with_agent: true)
      store = Textus::Store.new(root)

      Textus::Ports::BuildLock.with(root: root) do
        expect { store.as("automation").build }.to raise_error(Textus::BuildInProgress)
      end
    end
  end
end
