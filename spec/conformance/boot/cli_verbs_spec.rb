require "spec_helper"

# Top-level commands deliberately NOT surfaced in the agent-facing catalog:
# internal/maintenance/transport verbs an agent should not be steered toward.
# `watch` is the long-running convergence daemon — a process, not an agent-facing
# command — so it is deliberately omitted from the boot catalog.
BOOT_GUARD_INTENTIONALLY_OMITTED =
  %w[deps rdeps init mcp published reject data watch].freeze

RSpec.describe "Boot::CLI_VERBS — the agent-facing command catalog" do
  # Guard (ADR 0039): a verb's summary is a fact derived from its contract, not
  # editorial presentation. Where a boot catalog verb has a Dispatcher contract,
  # its surfaced summary must equal that contract's — and the curated source must
  # not carry a second hand-typed copy that could silently drift.
  describe "summaries derive from contracts (ADR 0039)" do
    let(:by_name) { Textus::Boot.contract_summaries }

    it "matches the contract summary for every catalog verb that has one" do
      drift = Textus::Boot::CLI_VERBS.filter_map do |v|
        want = by_name[v["name"]]
        next if want.nil? || want == v["summary"]

        "#{v["name"]}: catalog=#{v["summary"].inspect} contract=#{want.inspect}"
      end
      expect(drift).to be_empty, "CLI_VERBS summary drift:\n#{drift.join("\n")}"
    end

    it "carries no literal summary in the curated source for a verb that has a contract" do
      redundant = Textus::Boot::CURATED_CLI_VERBS.filter_map do |v|
        "#{v["name"]}: #{v["summary"].inspect}" if by_name.key?(v["name"]) && v.key?("summary")
      end
      expect(redundant).to be_empty,
                           "These curated verbs hand-type a summary their contract already owns:\n#{redundant.join("\n")}"
    end
  end

  # Guard (ADR 0034): the catalog avoids retired zone instance names.
  describe "avoids retired zone names (ADR 0034)" do
    include_context "textus_store_fixture"

    let(:store) do
      store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
        version: textus/4
        roles: [{ name: human, can: [author] }]
        lanes: [{ name: knowledge, kind: canon }]
        entries: []
      YAML
    end

    let(:verbs) do
      Textus::Boot::CLI_VERBS.to_h { |v| [v["name"], v["summary"]] }
    end

    it "describes accept as a queued-proposal promotion, not 'review.*'" do
      expect(verbs["accept"]).not_to include("review")
      expect(verbs["accept"]).to include("proposal")
    end

    it "build verb is absent from the CLI verbs list (ADR 0087)" do
      expect(verbs).not_to have_key("build")
    end

    it "describes pulse without the bare 'review' instance name" do
      expect(verbs["pulse"]).not_to include("review")
    end
  end

  # Guard (ADR 0037): Boot::CLI_VERBS is a curated, hand-written agent-facing
  # catalog — summaries stay editorial, but the SET OF NAMES must stay reconciled
  # with the real top-level command registry Textus::Surfaces::CLI.verbs. Adding a top-level
  # verb forces a choice: surface it in CLI_VERBS, or list it as intentionally
  # omitted. Either way, drift becomes a red test, not a silent stale catalog.
  describe "reconciles with the CLI registry (ADR 0037)" do
    let(:registry_names) { Textus::Surfaces::CLI.verbs.keys.sort }
    let(:catalog_names)  { Textus::Boot::CLI_VERBS.map { |v| v["name"] }.sort }

    it "every catalog verb is a real registered command" do
      ghosts = catalog_names - registry_names
      expect(ghosts).to be_empty,
                        "CLI_VERBS lists names with no Textus::Surfaces::CLI.verbs entry: #{ghosts.inspect}"
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
end
