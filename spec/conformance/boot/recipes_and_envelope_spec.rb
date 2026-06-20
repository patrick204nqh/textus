require "spec_helper"

BOOT_RECIPES_SPEC_MD = File.expand_path("../../../SPEC.md", __dir__)

RSpec.describe "Boot recipes & envelope — agent-facing protocol surface" do
  # Guard: agent-facing recipe steps must never name a deleted verb (fetch_all,
  # removed in ADR 0079). Recipes are surfaced under agent_protocol.recipes.
  describe "name no deleted verbs" do
    include_context "textus_store_fixture"

    before do
      FileUtils.mkdir_p(File.join(root, "data/intake"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/4
        roles:
          - { name: human,      can: [author, propose] }
          - { name: automation, can: [converge] }
        lanes:
          - { name: identity, kind: canon, desc: "human-only" }
          - { name: intake,   kind: machine }
      YAML
    end

    let(:store) { Textus::Store.new(root) }
    let(:drain_recipe) { Textus::Boot.build(container: store.container)["agent_protocol"]["recipes"]["drain"] }
    let(:steps_text) { drain_recipe["steps"].join("\n") }

    it "the refresh recipe does not call fetch_all" do
      expect(steps_text).not_to include("fetch_all")
    end

    it "the refresh recipe re-pulls stale entries via drain" do
      expect(steps_text).to include("drain")
    end
  end

  # Guard (ADR 0034): recipes name live zones, not retired instance names.
  describe "name live zones (ADR 0034)" do
    include_context "textus_store_fixture"

    let(:store) do
      store_from_manifest(root, lanes: %w[knowledge feeds proposals], manifest: <<~YAML)
        version: textus/4
        roles:
          - { name: human,      can: [author, propose] }
          - { name: agent,      can: [propose] }
          - { name: automation, can: [converge] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: feeds,     kind: machine }
          - { name: proposals, kind: queue }
        entries: []
      YAML
    end

    let(:recipes) { Textus::Boot.build(container: store.container)["agent_protocol"]["recipes"] }

    it "names the live queue zone in the propose recipe" do
      text = recipes["propose"].values_at("agent_steps", "human_steps").flatten.join(" ")
      expect(text).to include("proposals.KEY")
      expect(text).not_to include("review.KEY")
    end

    it "names the live machine zone in the drain recipe" do
      text = recipes["drain"]["steps"].join(" ")
      expect(text).to include("feeds")
      expect(text).not_to include("intake")
    end

    it "phrases steps as verbs, not transport CLI strings (ADR 0056)" do
      steps = recipes.values.flat_map { |r| r.values_at("steps", "agent_steps", "human_steps").compact.flatten }
      expect(steps).to all(satisfy { |s| !s.start_with?("textus ") && !s.include?("| textus ") })
    end
  end

  # ADR 0056: boot's agent-facing surface must speak the MCP catalog, not a
  # hand-maintained CLI dialect. These guards fail the build if read_verbs drifts
  # from the agent's real callable surface, or if a recipe references a verb the
  # agent cannot call — the exact regression that sent schema discovery through a
  # CLI shell-out in downstream skills.
  describe "agent quickstart / recipes — derive-or-guard (ADR 0056)" do
    include_context "textus_store_fixture"

    let(:store) do
      store_from_manifest(root, lanes: %w[knowledge feeds proposals], manifest: <<~YAML)
        version: textus/4
        roles:
          - { name: human,      can: [author, propose] }
          - { name: agent,      can: [propose] }
          - { name: automation, can: [converge] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: feeds,     kind: machine }
          - { name: proposals, kind: queue }
        entries: []
      YAML
    end

    let(:boot) { Textus::Boot.build(container: store.container) }
    let(:read_verbs) { boot["agent_quickstart"]["read_verbs"] }
    let(:write_verbs) { boot["agent_quickstart"]["write_verbs"] }
    let(:recipes) { boot["agent_protocol"]["recipes"] }

    it "advertises only verbs the agent can actually call over MCP" do
      expect(Textus::Surface::MCP::Catalog.names).to include(*read_verbs)
    end

    # ADR 0057: write_verbs derives from the catalog too — bare verb names, never
    # CLI strings. The guard fails the build if a `--as`/`--stdin` invocation
    # creeps back into the agent's write surface.
    it "advertises write_verbs as MCP-callable verbs, never CLI strings" do
      expect(Textus::Surface::MCP::Catalog.names).to include(*write_verbs)
      expect(write_verbs).to include("put", "propose")
      expect(write_verbs).to all(match(/\A\w+\z/))
    end

    it "advertises the discovery verbs the write/propose flow depends on" do
      expect(read_verbs).to include("schema_show", "rule_explain", "deps", "rdeps", "where")
    end

    it "never advertises CLI-only read verbs as agent verbs" do
      expect(read_verbs).not_to include("audit", "freshness", "doctor")
    end

    it "references only MCP-callable verbs in its agent-facing recipe steps" do
      # `human_steps` are the human/CLI channel (e.g. `accept`, an author-only
      # transition that is deliberately not an MCP tool — ADR 0035/0040), so the
      # guard covers only the steps an agent executes.
      known = Textus::Action::VERBS.keys.map(&:to_s)
      referenced = recipes.values
                          .flat_map { |r| r.values_at("steps", "agent_steps").compact.flatten }
                          .filter_map { |s| s[/\A(\w+)/, 1] }
                          .select { |tok| known.include?(tok) }
      expect(referenced).not_to be_empty
      expect(Textus::Surface::MCP::Catalog.names).to include(*referenced)
    end
  end

  # Guard (ADR 0037): SPEC §9's hand-written pulse / agent_quickstart example JSON
  # must stay a faithful snapshot of the live envelope key sets. The doc examples
  # are extracted by anchored text and their key sets compared to reality.
  describe "SPEC §9 examples snapshot the live envelope keys (ADR 0037)" do
    include_context "textus_store_fixture"

    before do
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/4
        roles:
          - { name: human, can: [author, propose] }
          - { name: agent, can: [propose] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: proposals,  kind: queue }
        entries: []
      YAML
    end

    let(:store) { Textus::Store.new(root) }

    # Parsed JSON object from the first ```json fenced block after `anchor`.
    # Captures the whole fenced body (not brace-matched) so nested braces are safe.
    def json_block_after(anchor)
      text  = File.read(BOOT_RECIPES_SPEC_MD)
      start = text.index(anchor) or raise "anchor not found in SPEC.md: #{anchor.inspect}"
      block = text[start..].match(/```json\s*\n(.*?)\n```/m) or raise "no json block after #{anchor.inspect}"
      JSON.parse(block[1])
    end

    it "pulse example documents exactly the keys Read::Pulse#call returns" do
      live = store.as("human").pulse(since: 0).keys.sort
      documented = json_block_after("`textus pulse` output shape").keys.sort
      expect(documented).to eq(live),
                            "SPEC §9 pulse example keys #{documented.inspect} != live #{live.inspect}"
    end

    it "agent_quickstart example documents exactly the keys boot synthesizes" do
      live = store.as("human").boot["agent_quickstart"].keys.sort
      documented = json_block_after("`textus boot` envelope extras").fetch("agent_quickstart").keys.sort
      expect(documented).to eq(live),
                            "SPEC §9 agent_quickstart example keys #{documented.inspect} != live #{live.inspect}"
    end
  end
end
