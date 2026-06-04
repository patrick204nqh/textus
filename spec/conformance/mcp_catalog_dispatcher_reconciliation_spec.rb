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
# build is NO LONGER here: it is surfaced to MCP per ADR 0076 — it runs as the
# manifest's build actor (caller-agnostic, self-elevating) and is serialized by
# a shared around :build_lock resource across all transports.
MCP_CATALOG_INTENTIONALLY_OMITTED = %w[
  audit blame uid freshness
  doctor rule_list published
  validate_all
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

  it "maps the public `get` verb to the read-through use-case (ADR 0062)" do
    expect(Textus::Dispatcher::VERBS[:get]).to eq(Textus::Read::Get)
    expect(Textus::Dispatcher::VERBS).not_to have_key(:get_or_fetch)
  end
end
