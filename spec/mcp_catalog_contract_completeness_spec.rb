require "spec_helper"

# Guard (ADR 0039): the floor for the residue derivation can't cover. A verb
# marked surfaces(:mcp) must declare a contract; if its raw return value is not
# already JSON-encodable it must declare a default `view` shaper. A verb added to
# the dispatcher with no contract cannot be reached by MCP, but this guard also
# stops a half-declared contract (surfaces :mcp but unusable) from shipping.
RSpec.describe "MCP-surfaced verbs are completely declared (ADR 0039)" do
  let(:mcp_specs) { Textus::MCP::Catalog.specs }

  it "exposes at least the core read/write verbs" do
    expect(Textus::MCP::Catalog.names).to include("boot", "pulse", "list", "get", "put", "propose")
  end

  it "every MCP spec has a non-empty summary" do
    bad = mcp_specs.reject { |s| s.summary.is_a?(String) && !s.summary.empty? }.map(&:verb)
    expect(bad).to be_empty, "MCP verbs missing a summary: #{bad.inspect}"
  end

  it "every MCP spec's inputSchema is well-formed JSON-Schema" do
    mcp_specs.each do |s|
      schema = s.input_schema
      expect(schema[:type]).to eq("object")
      expect(schema[:properties]).to be_a(Hash)
      expect(schema[:required]).to all(be_a(String))
    end
  end

  it "every MCP spec carries a callable default view shaper" do
    expect(mcp_specs.map { |s| s.view(:default) }).to all(respond_to(:call))
  end
end
