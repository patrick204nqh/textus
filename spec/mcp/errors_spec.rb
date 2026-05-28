require "spec_helper"

RSpec.describe Textus::MCP do
  it "defines ContractDrift as a Textus::Error" do
    err = Textus::MCP::ContractDrift.new("manifest changed")
    expect(err).to be_a(Textus::Error)
    expect(err.message).to eq("manifest changed")
    expect(Textus::MCP::ContractDrift::JSONRPC_CODE).to eq(-32_001)
  end

  it "defines CursorExpired with JSON-RPC code -32002" do
    expect(Textus::MCP::CursorExpired::JSONRPC_CODE).to eq(-32_002)
  end

  it "defines ToolError with JSON-RPC code -32000" do
    expect(Textus::MCP::ToolError::JSONRPC_CODE).to eq(-32_000)
  end
end
