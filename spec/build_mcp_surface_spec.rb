require "spec_helper"

RSpec.describe "build is reachable from MCP" do
  it "declares the :mcp surface" do
    expect(Textus::Write::Build.contract.surfaces).to include(:mcp)
    expect(Textus::Write::Build.contract.mcp?).to be true
  end
end
