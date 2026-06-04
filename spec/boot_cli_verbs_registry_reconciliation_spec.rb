require "spec_helper"

# Guard (ADR 0037): Boot::CLI_VERBS is a curated, hand-written agent-facing
# catalog — summaries stay editorial, but the SET OF NAMES must stay reconciled
# with the real top-level command registry Textus::CLI.verbs. Adding a top-level
# verb forces a choice: surface it in CLI_VERBS, or list it as intentionally
# omitted below. Either way, drift becomes a red test, not a silent stale catalog.

# Top-level commands deliberately NOT surfaced in the agent-facing catalog:
# internal/maintenance/transport verbs an agent should not be steered toward.
BOOT_GUARD_INTENTIONALLY_OMITTED =
  %w[deps rdeps init mcp migrate published reject zone].freeze

RSpec.describe "Boot::CLI_VERBS reconciles with the CLI registry (ADR 0037)" do
  let(:registry_names) { Textus::CLI.verbs.keys.sort }
  let(:catalog_names)  { Textus::Boot::CLI_VERBS.map { |v| v["name"] }.sort }

  it "every catalog verb is a real registered command" do
    ghosts = catalog_names - registry_names
    expect(ghosts).to be_empty,
                      "CLI_VERBS lists names with no Textus::CLI.verbs entry: #{ghosts.inspect}"
  end

  it "every registered command is either in the catalog or explicitly omitted" do
    unaccounted = registry_names - catalog_names - BOOT_GUARD_INTENTIONALLY_OMITTED
    expect(unaccounted).to be_empty,
                           "new top-level verb(s) #{unaccounted.inspect}: " \
                           "add to Boot::CLI_VERBS or to BOOT_GUARD_INTENTIONALLY_OMITTED"
  end

  it "the omit-list contains no stale entries (all still registered)" do
    stale = BOOT_GUARD_INTENTIONALLY_OMITTED - registry_names
    expect(stale).to be_empty,
                     "omit-list names no longer registered: #{stale.inspect}"
  end
end
