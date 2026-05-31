require "spec_helper"

# Floor guard (ADR 0039): the two hand-maintained MCP halves — the dispatch
# table and the advertised JSON schemas — must name the exact same tool set.
# A tool you can call but not discover (or discover but not call) is drift.
# This guard survives Phase B (Catalog derivation) because both sides then
# derive from one source and parity is automatic — the spec just keeps proving it.
RSpec.describe "MCP REGISTRY and ToolSchemas name the same tools (ADR 0039)" do
  let(:registry_names) { Textus::MCP::Tools.build_registry.keys.sort }
  let(:schema_names)   { Textus::MCP::ToolSchemas.all.map { |t| t[:name] }.sort }

  it "advertises exactly the tools it can dispatch" do
    expect(schema_names).to eq(registry_names),
                            "dispatch table vs advertised schemas mismatch: " \
                            "only-in-registry=#{(registry_names - schema_names).inspect} " \
                            "only-in-schemas=#{(schema_names - registry_names).inspect}"
  end
end
