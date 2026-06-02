require "spec_helper"

# ADR 0056: boot's agent-facing surface must speak the MCP catalog, not a
# hand-maintained CLI dialect. These guards fail the build if read_verbs drifts
# from the agent's real callable surface, or if a recipe references a verb the
# agent cannot call — the exact regression that sent schema discovery through a
# CLI shell-out in downstream skills.
RSpec.describe "boot agent quickstart / recipes — derive-or-guard (ADR 0056)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge feeds proposals], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose] }
        - { name: automation, can: [fetch, build] }
      zones:
        - { name: knowledge, kind: canon }
        - { name: feeds,     kind: quarantine }
        - { name: proposals, kind: queue }
      entries: []
    YAML
  end

  let(:boot) { Textus::Boot.build(container: store.container) }
  let(:read_verbs) { boot["agent_quickstart"]["read_verbs"] }
  let(:write_verbs) { boot["agent_quickstart"]["write_verbs"] }
  let(:recipes) { boot["agent_protocol"]["recipes"] }

  it "advertises only verbs the agent can actually call over MCP" do
    expect(Textus::MCP::Catalog.names).to include(*read_verbs)
  end

  # ADR 0057: write_verbs derives from the catalog too — bare verb names, never
  # CLI strings. The guard fails the build if a `--as`/`--stdin` invocation
  # creeps back into the agent's write surface.
  it "advertises write_verbs as MCP-callable verbs, never CLI strings" do
    expect(Textus::MCP::Catalog.names).to include(*write_verbs)
    expect(write_verbs).to include("put", "propose")
    expect(write_verbs).to all(match(/\A\w+\z/))
  end

  it "advertises the discovery verbs the write/propose flow depends on" do
    expect(read_verbs).to include("schema", "rules")
  end

  it "never advertises CLI-only read verbs as agent verbs" do
    expect(read_verbs).not_to include("audit", "freshness", "doctor")
  end

  it "references only MCP-callable verbs in its agent-facing recipe steps" do
    # `human_steps` are the human/CLI channel (e.g. `accept`, an author-only
    # transition that is deliberately not an MCP tool — ADR 0035/0040), so the
    # guard covers only the steps an agent executes.
    known = Textus::Dispatcher::VERBS.keys.map(&:to_s)
    referenced = recipes.values
                        .flat_map { |r| r.values_at("steps", "agent_steps").compact.flatten }
                        .filter_map { |s| s[/\A(\w+)/, 1] }
                        .select { |tok| known.include?(tok) }
    expect(referenced).not_to be_empty
    expect(Textus::MCP::Catalog.names).to include(*referenced)
  end
end
