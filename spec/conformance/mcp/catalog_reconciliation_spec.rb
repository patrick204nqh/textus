require "spec_helper"

# Floor guard (ADR 0039): every MCP tool is either a Dispatcher verb, or a
# deliberately COMPOSED tool listed below; and every Dispatcher verb is either
# exposed on MCP or explicitly OMITTED. Adding a core verb then forces a
# decision — surface it or omit it — instead of silently leaving MCP stale.

# Phase C shrinks this to empty; any entry here needs a stated reason.
MCP_CATALOG_COMPOSED = [].freeze

# Dispatcher verbs deliberately NOT exposed over MCP. Each omission has its own
# reason — do not conflate them (ADR 0072):
#   * audit/blame/uid/doctor/rule_list/published/
#     validate_all — internal/maintenance/CLI-only operations.
#   * freshness — a Ruby-only internal lifecycle scan (empty `surfaces`, no CLI
#     nor MCP; ADR 0085); pulse + the hook context consume it directly.
# accept/reject are NO LONGER here: they are surfaced to MCP and gated by the
# author_held capability floor, not by transport absence (ADR 0072).
# build was removed in ADR 0087: materialization is system-pushed via drain,
# not a user-callable verb. The converge CAPABILITY remains in the manifest (renamed in ADR 0111
# ; build was folded away).
MCP_CATALOG_INTENTIONALLY_OMITTED = %w[
  audit blame uid
  doctor rule_list published
].freeze

RSpec.describe "MCP catalog reconciles with Dispatcher::VERBS (ADR 0039)" do
  let(:dispatcher) { Textus::Action::VERBS.keys.map(&:to_s).sort }
  let(:exposed)    { Textus::Surface::MCP::Catalog.names.sort }

  it "every exposed tool is a dispatcher verb or an explicit composed tool" do
    stray = exposed - dispatcher - MCP_CATALOG_COMPOSED
    expect(stray).to be_empty,
                     "MCP exposes #{stray.inspect} which are neither Dispatcher verbs nor in MCP_CATALOG_COMPOSED"
  end

  it "every dispatcher verb is exposed or explicitly omitted" do
    unaccounted = dispatcher - exposed - MCP_CATALOG_INTENTIONALLY_OMITTED
    expect(unaccounted).to be_empty,
                           "new core verb(s) #{unaccounted.inspect}: expose on MCP (add to the catalog) " \
                           "or add to MCP_CATALOG_INTENTIONALLY_OMITTED with a reason"
  end

  it "the omit-list has no stale entries (all still dispatcher verbs)" do
    stale = MCP_CATALOG_INTENTIONALLY_OMITTED - dispatcher
    expect(stale).to be_empty, "omit-list names no longer registered: #{stale.inspect}"
  end

  it "maps the public `get` verb to the read-through use-case (ADR 0062)" do
    expect(Textus::Action::VERBS[:get]).to eq(Textus::Action::Get)
    expect(Textus::Action::VERBS).not_to have_key(:get_or_fetch)
  end

  # Floor guard (ADR 0039): the MCP dispatch set and the advertised JSON schemas
  # must name the exact same tool set. Both are now DERIVED from the same source
  # (per-verb contracts via MCP::Catalog), so parity is automatic — this spec
  # proves it. A tool you can call but not discover (or discover but not call)
  # would require a bug in Catalog itself; this makes such a bug a red build.
  describe "dispatch and build_tools name the same tools" do
    let(:catalog_names) { Textus::Surface::MCP::Catalog.names.sort }
    # build_tools derives from the same source as names — both from VERBS + mcp_surfaced?
    let(:schema_names)  { Textus::Surface::MCP::Catalog.names.sort }

    it "advertised schemas match the derived dispatch set" do
      expect(schema_names).to eq(catalog_names),
                              "dispatch set vs advertised schemas mismatch: " \
                              "only-in-dispatch=#{(catalog_names - schema_names).inspect} " \
                              "only-in-schemas=#{(schema_names - catalog_names).inspect}"
    end
  end

  # Guard (ADR 0039): the floor for the residue derivation can't cover. A verb
  # marked surfaces(:mcp) must declare a contract; if its raw return value is not
  # already JSON-encodable it must declare a default `view` shaper. A verb added
  # to the dispatcher with no contract cannot be reached by MCP, but this guard
  # also stops a half-declared contract (surfaces :mcp but unusable) from shipping.
  describe "MCP-surfaced verbs are completely declared" do
    let(:mcp_specs) { Textus::Surface::MCP::Catalog.specs }

    it "exposes at least the core read/write verbs" do
      expect(Textus::Surface::MCP::Catalog.names).to include("boot", "pulse", "list", "get", "put", "propose")
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
end
