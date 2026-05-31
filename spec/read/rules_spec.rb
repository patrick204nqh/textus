require "spec_helper"

RSpec.describe Textus::Read::Rules do
  let(:store) { Textus::Store.discover(File.expand_path("../../examples/project", __dir__)) }

  it "returns the effective fetch/guard rule set for a key" do
    out = store.as("human").rules("knowledge.project")
    expect(out).to be_a(Hash)
    expect(out.keys - %w[fetch guard]).to be_empty
  end

  it "declares an MCP contract" do
    expect(described_class.contract.verb).to eq(:rules)
    expect(described_class.contract.mcp?).to be(true)
    expect(described_class.contract.args.map(&:name)).to eq([:key])
  end
end
