require "spec_helper"

# Floor guard (ADR 0039): the MCP dispatch set and the advertised JSON schemas
# must name the exact same tool set. Both are now DERIVED from the same source
# (per-verb contracts via MCP::Catalog), so parity is automatic — this spec
# proves it. A tool you can call but not discover (or discover but not call)
# would require a bug in Catalog itself; this makes such a bug a red build.
RSpec.describe "MCP dispatch and ToolSchemas name the same tools (ADR 0039)" do
  let(:catalog_names) { Textus::MCP::Catalog.names.sort }
  let(:schema_names)  { Textus::MCP::ToolSchemas.all.map { |t| t[:name] }.sort }

  it "advertised schemas match the derived dispatch set" do
    expect(schema_names).to eq(catalog_names),
                            "dispatch set vs advertised schemas mismatch: " \
                            "only-in-dispatch=#{(catalog_names - schema_names).inspect} " \
                            "only-in-schemas=#{(schema_names - catalog_names).inspect}"
  end
end
