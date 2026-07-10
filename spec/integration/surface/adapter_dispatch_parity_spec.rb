require "spec_helper"

RSpec.describe "surface adapter dispatch parity" do
  include_context "textus/4 conformance fixture"

  it "CLI and MCP produce same protocol for boot" do
    cli_out = StringIO.new
    Textus::Surface::CLI.run(["boot"], stdin: StringIO.new(""), stdout: cli_out, stderr: StringIO.new, cwd: tmp)
    cli = JSON.parse(cli_out.string)

    api = Textus::API.new(gate: store.gate, store:)
    mcp_adapter = Textus::Adapters::McpAdapter.new(api:)
    mcp = mcp_adapter.call(:boot, role: "agent")

    expect(cli["protocol"]).to eq("textus/4")
    expect(mcp["protocol"]).to eq("textus/4")
  end

  it "CLI and MCP both can get a stored value" do
    store.put(key: "knowledge.constraint", _meta: {}, data: "parity")

    cli_out = StringIO.new
    Textus::Surface::CLI.run(["get", "knowledge.constraint"], stdin: StringIO.new(""), stdout: cli_out, stderr: StringIO.new, cwd: tmp)
    cli_body = JSON.parse(cli_out.string)["body"]

    api = Textus::API.new(gate: store.gate, store:)
    mcp_adapter = Textus::Adapters::McpAdapter.new(api:)
    mcp = mcp_adapter.call(:get, params: { "key" => "knowledge.constraint" }, role: "agent")
    mcp_body = mcp["body"]

    expect(cli_body).to eq(mcp_body)
  end
end
