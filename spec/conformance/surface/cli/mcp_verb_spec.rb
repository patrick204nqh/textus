require "spec_helper"

RSpec.describe "textus mcp serve" do
  it "registers the verb under the mcp group" do
    expect(Textus::Surface::CLI::Group::MCP.command_name).to eq("mcp")
    expect(Textus::Surface::CLI::Verb::MCPServe.command_name).to eq("serve")
  end
end
