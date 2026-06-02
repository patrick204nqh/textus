require "spec_helper"

RSpec.describe Textus::MCP::ToolSchemas do
  describe ".all" do
    # This assertion is self-updating: it delegates to Catalog.names, so adding
    # a new MCP-surfaced contract automatically expands both sides (ADR 0039).
    it "names exactly match the derived catalog names" do
      expect(described_class.all.map { |t| t[:name] }.sort)
        .to eq(Textus::MCP::Catalog.names.sort),
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
                               "fetch", "fetch_all", "propose", "schema_show", "rules")
      expect(names).not_to include("tick", "find", "read", "write", "fetch_stale")
    end

    it "exposes the maintenance tools" do
      names = described_class.all.map { |t| t[:name] }
      expect(names).to include("key_mv_prefix", "key_delete_prefix",
                               "zone_mv", "rule_lint", "migrate")
    end

    it "marks key-required tools' inputSchema with required: ['key']" do
      get = described_class.all.find { |t| t[:name] == "get" }
      expect(get[:inputSchema][:required]).to eq(["key"])
    end

    it "boot tool takes no arguments" do
      boot = described_class.all.find { |t| t[:name] == "boot" }
      expect(boot[:inputSchema][:properties]).to eq({})
      expect(boot[:inputSchema][:required]).to eq([])
    end
  end
end
