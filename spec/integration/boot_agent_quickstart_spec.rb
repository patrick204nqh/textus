require "spec_helper"

RSpec.describe Textus::Boot do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/proposals"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals,  kind: queue }
      entries: []
    YAML
  end

  describe ".run / agent_quickstart" do
    it "exposes agent_quickstart with read_verbs, write_verbs, writable_lanes, propose_lane, latest_seq", :aggregate_failures do
      out = described_class.build(container: Textus::Store.new(root).container)
      qs = out["agent_quickstart"]
      expect(qs).to be_a(Hash)
      # read_verbs derives from the MCP catalog (ADR 0056): the verbs the agent
      # can actually call — including schema/rule_explain and the graph reads
      # (deps/rdeps/where, ADR 0060) — and never audit/doctor (CLI-only) nor
      # freshness (a Ruby-only internal scan, ADR 0085).
      expect(qs["read_verbs"]).to include("boot", "get", "list", "pulse", "schema_show",
                                          "rule_explain", "deps", "rdeps", "where")
      expect(qs["read_verbs"]).not_to include("audit", "freshness", "doctor")
      # write_verbs derives from the MCP catalog too (ADR 0057): bare verb names
      # the agent calls — not the old `put KEY --as=agent --stdin` CLI string.
      # accept/reject are advertised even though this agent lacks `author`
      # (ADR 0072): the verbs are reachable; the author_held guard refuses them
      # at call time — the boundary is self-documenting, not hidden by absence.
      expect(qs["write_verbs"]).to include("put", "propose", "accept", "reject")
      expect(qs["write_verbs"]).not_to include(a_string_matching(/--as=|--stdin/))
      expect(qs["writable_lanes"]).to include("proposals")
      expect(qs["propose_lane"]).to eq("proposals")
      expect(qs).to have_key("latest_seq")
      expect(qs["latest_seq"]).to be_a(Integer)
    end

    it "pulse is in the CLI_VERBS constant" do
      names = Textus::Boot::CLI_VERBS.map { |v| v["name"] }
      expect(names).to include("pulse")
    end

    it "handles manifests with no proposer role gracefully" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: human, can: [author] }
        lanes:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      out = described_class.build(container: Textus::Store.new(root).container)
      qs = out["agent_quickstart"]
      expect(qs["write_verbs"]).to eq([])
      expect(qs["writable_lanes"]).to eq([])
      expect(qs["propose_lane"]).to be_nil
    end
  end
end
