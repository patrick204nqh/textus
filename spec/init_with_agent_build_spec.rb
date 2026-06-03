# spec/init_with_agent_build_spec.rb
require "spec_helper"

RSpec.describe "init --with-agent produces a buildable orientation" do
  it "publishes CLAUDE.md and AGENTS.md from authored canon" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root, with_agent: true)

      store = Textus::Store.new(root)
      store.as("human").put(
        "knowledge.project",
        meta: { "name" => "project", "description" => "double-entry accounting service" },
        body: "",
      )
      store.as("human").put(
        "knowledge.runbooks.deploy",
        meta: { "name" => "deploy", "description" => "ship a release" },
        body: "steps...\n",
      )

      store.as("automation").build

      claude = File.join(dir, "CLAUDE.md")
      agents = File.join(dir, "AGENTS.md")
      expect(File.exist?(claude)).to be true
      expect(File.exist?(agents)).to be true
      expect(File.read(claude)).to include("# project")
      expect(File.read(claude)).to include("**deploy** — ship a release")
    end
  end
end
