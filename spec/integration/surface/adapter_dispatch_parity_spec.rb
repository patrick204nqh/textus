require "spec_helper"

RSpec.describe "surface adapter dispatch parity" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "CLI and MCP produce same protocol for boot" do
    store.put(key: "knowledge.foo", _meta: {}, body: "parity")

    cli_out = StringIO.new
    Textus::Surface::CLI.run(["boot", "--output=json"],
                             stdin: StringIO.new(""), stdout: cli_out, stderr: StringIO.new,
                             cwd: tmp)
    cli = JSON.parse(cli_out.string)

    mcp = Textus::Surface::MCP::Projector.new.dispatch(:boot, inputs: {}, store: store)

    expect(cli["protocol"]).to eq("textus/4")
    expect(mcp["protocol"]).to eq("textus/4")
  end

  it "CLI and MCP both can get a stored value" do
    store.put(key: "knowledge.foo", _meta: {}, body: "parity")

    cli_out = StringIO.new
    Textus::Surface::CLI.run(["get", "knowledge.foo", "--output=json"],
                             stdin: StringIO.new(""), stdout: cli_out, stderr: StringIO.new,
                             cwd: tmp)
    cli_body = JSON.parse(cli_out.string)["body"]

    mcp = Textus::Surface::MCP::Projector.new.dispatch(:get, inputs: { "key" => "knowledge.foo" }, store: store)
    mcp_body = mcp["body"]

    expect(cli_body).to eq(mcp_body)
  end
end
