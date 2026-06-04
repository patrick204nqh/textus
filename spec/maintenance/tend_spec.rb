require "spec_helper"

RSpec.describe Textus::Maintenance::Tend do
  it "is registered as a dispatcher verb and a RoleScope method" do
    expect(Textus::Dispatcher::VERBS).to include(:tend)
    expect(Textus::Dispatcher::VERBS[:tend]).to eq(described_class)
    expect(Textus::RoleScope.instance_methods).to include(:tend)
  end

  it "declares a contract surfaced on both CLI and MCP" do
    spec = described_class.contract
    expect(spec.verb).to eq(:tend)
    expect(spec.cli?).to be(true)
    expect(spec.mcp?).to be(true)
  end
end
