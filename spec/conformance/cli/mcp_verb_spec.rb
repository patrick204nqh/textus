require "spec_helper"

RSpec.describe "textus mcp serve" do
  it "registers the verb under the mcp group" do
    expect(Textus::Surfaces::CLI::Group::MCP.command_name).to eq("mcp")
    expect(Textus::Surfaces::CLI::Verb::MCPServe.command_name).to eq("serve")
  end
end
