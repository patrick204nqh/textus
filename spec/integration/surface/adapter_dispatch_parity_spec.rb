require "spec_helper"

RSpec.describe "surface adapter dispatch parity" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "CLI and MCP produce same protocol for boot" do
    store.put(key: "knowledge.foo", _meta: {}, data: "parity")

    cli_out = StringIO.new
    Textus::Surface::CLI.run(["boot"], stdin: StringIO.new(""), stdout: cli_out, stderr: StringIO.new, cwd: tmp)
    cli = JSON.parse(cli_out.string)

    mcp_adapter = Textus::Adapters::McpAdapter.new
    mcp_response = mcp_adapter.call("boot", gate: store.gate, role: "agent")
    mcp = mcp_response.payload

    expect(cli["protocol"]).to eq("textus/4")
    expect(mcp["protocol"]).to eq("textus/4")
  end

  it "CLI and MCP both can get a stored value" do
    store.put(key: "knowledge.foo", _meta: {}, data: "parity")

    cli_out = StringIO.new
    Textus::Surface::CLI.run(["get", "knowledge.foo"], stdin: StringIO.new(""), stdout: cli_out, stderr: StringIO.new, cwd: tmp)
    cli_body = JSON.parse(cli_out.string)["body"]

    mcp_adapter = Textus::Adapters::McpAdapter.new
    mcp_response = mcp_adapter.call("get", params: { "key" => "knowledge.foo" }, gate: store.gate, role: "agent")
    mcp_body = mcp_response.payload["body"]

    expect(cli_body).to eq(mcp_body)
  end
end
