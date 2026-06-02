require "spec_helper"

RSpec.describe Textus::Boot do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/proposals"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: knowledge, kind: canon }
        - { name: proposals,  kind: queue }
      entries: []
    YAML
  end

  describe ".run / agent_quickstart" do
    it "exposes agent_quickstart with read_verbs, write_verbs, writable_zones, propose_zone, latest_seq" do
      out = described_class.build(container: Textus::Store.new(root).container)
      qs = out["agent_quickstart"]
      expect(qs).to be_a(Hash)
      # read_verbs derives from the MCP catalog (ADR 0056): the verbs the agent
      # can actually call — including schema/rules — and never the CLI-only
      # audit/freshness/doctor.
      expect(qs["read_verbs"]).to include("boot", "get", "list", "pulse", "schema_show", "rules")
      expect(qs["read_verbs"]).not_to include("audit", "freshness", "doctor")
      # write_verbs derives from the MCP catalog too (ADR 0057): bare verb names
      # the agent calls — not the old `put KEY --as=agent --stdin` CLI string.
      expect(qs["write_verbs"]).to include("put", "propose")
      expect(qs["write_verbs"]).not_to include(a_string_matching(/--as=|--stdin/))
      expect(qs["writable_zones"]).to include("proposals")
      expect(qs["propose_zone"]).to eq("proposals")
      expect(qs).to have_key("latest_seq")
      expect(qs["latest_seq"]).to be_a(Integer)
    end

    it "includes pulse in the cli_verbs list" do
      out = described_class.build(container: Textus::Store.new(root).container)
      names = out["cli_verbs"].map { |v| v["name"] }
      expect(names).to include("pulse")
    end

    it "handles manifests with no proposer role gracefully" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: human, can: [author] }
        zones:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      out = described_class.build(container: Textus::Store.new(root).container)
      qs = out["agent_quickstart"]
      expect(qs["write_verbs"]).to eq([])
      expect(qs["writable_zones"]).to eq([])
      expect(qs["propose_zone"]).to be_nil
    end
  end
end
