require "spec_helper"

RSpec.describe Textus::Surfaces::MCP::ToolSchemas do
  describe ".all" do
    # This assertion is self-updating: it delegates to Catalog.names, so adding
    # a new MCP-surfaced contract automatically expands both sides (ADR 0039).
    it "names exactly match the derived catalog names" do
      expect(described_class.all.map { |t| t[:name] }.sort)
        .to eq(Textus::Surfaces::MCP::Catalog.names.sort),
            "ToolSchemas.all and Catalog.names disagree — check contract surfaces declarations"
    end

    it "returns one entry per tool, each with name/description/inputSchema" do
      described_class.all.each do |t|
        expect(t).to include(:name, :description, :inputSchema)
        expect(t[:inputSchema][:type]).to eq("object")
        expect(t[:description]).to be_a(String).and(satisfy("non-empty") { |s| !s.empty? })
      end
    end

    it "exposes the current core read/write verbs (not retired ADR 0036 aliases)" do
      names = described_class.all.map { |t| t[:name] }
      expect(names).to include("boot", "pulse", "list", "get", "put",
                               "propose", "accept", "reject",
                               "schema_show", "rule_explain", "deps", "rdeps", "where")
      expect(names).not_to include("tick", "find", "read", "write", "fetch_stale", "rules",
                                   "fetch", "fetch_all", "stale", "retainable", "retain")
    end

    it "exposes the maintenance tools" do
      names = described_class.all.map { |t| t[:name] }
      expect(names).to include("key_mv_prefix", "key_delete_prefix",
                               "data_mv", "rule_lint", "drain")
    end

    it "marks key-required tools' inputSchema with required: ['key']" do
      get = described_class.all.find { |t| t[:name] == "get" }
      expect(get[:inputSchema][:required]).to eq(["key"])
    end

    it "boot tool advertises the optional lean flag (ADR 0084)" do
      boot = described_class.all.find { |t| t[:name] == "boot" }
      expect(boot[:inputSchema][:properties]).to include("lean")
      expect(boot[:inputSchema][:required]).to eq([])
    end

    # The real guard here is the required-array assertions below; presence is belt-and-suspenders
    # (already covered by the catalog-parity test above).
    it "exposes single-key key_delete and key_mv (ADR 0060 amendment; renamed in ADR 0082)" do
      by_name = described_class.all.to_h { |t| [t[:name], t] }
      expect(by_name).to include("key_delete", "key_mv")
      expect(by_name["key_delete"][:inputSchema][:required]).to eq(["key"])
      expect(by_name["key_mv"][:inputSchema][:required]).to eq(%w[old_key new_key])
    end
  end
end
