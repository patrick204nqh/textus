require "spec_helper"

# Floor guard (ADR 0039): every MCP tool is either a Dispatcher verb, or a
# deliberately COMPOSED tool listed below; and every Dispatcher verb is either
# exposed on MCP or explicitly OMITTED. Adding a core verb then forces a
# decision — surface it or omit it — instead of silently leaving MCP stale.

# Phase C shrinks this to empty; any entry here needs a stated reason.
MCP_CATALOG_COMPOSED = [].freeze

# Dispatcher verbs deliberately NOT exposed over MCP: internal/maintenance/
# CLI-only operations an agent should not be steered toward. Reviewer must
# justify each. Edit this list when you add or expose a verb.
MCP_CATALOG_INTENTIONALLY_OMITTED = %w[
  accept reject publish delete mv
  audit blame deps rdeps where uid freshness stale
  doctor policy_explain published retainable
  get_or_fetch validate_all retention_sweep
].freeze

RSpec.describe "MCP catalog reconciles with Dispatcher::VERBS (ADR 0039)" do
  let(:dispatcher) { Textus::Dispatcher::VERBS.keys.map(&:to_s).sort }
  let(:exposed)    { Textus::MCP::Catalog.names.sort }

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
end
