require "spec_helper"

RSpec.describe Textus::MCP::ToolSchemas do
  describe ".all" do
    it "returns one entry per tool, each with name/description/inputSchema" do
      tools = described_class.all
      names = tools.map { |t| t[:name] }
      expect(names).to include("boot", "pulse", "list", "get", "put",
                               "fetch", "fetch_all")
      # propose/schema/rules are composed tools promoted in Phase C (ADR 0039)
      tools.each do |t|
        expect(t).to include(:name, :description, :inputSchema)
        expect(t[:inputSchema][:type]).to eq("object")
      end
    end

    it "exposes the core verb names, not the old MCP aliases" do
      names = described_class.all.map { |t| t[:name] }
      expect(names).to include("pulse", "list", "get", "put", "fetch_all")
      expect(names).not_to include("tick", "find", "read", "write", "fetch_stale")
    end

    it "still exposes the unchanged verbs and maintenance tools" do
      names = described_class.all.map { |t| t[:name] }
      # propose/schema/rules are composed tools promoted in Phase C (ADR 0039)
      expect(names).to include("boot", "fetch", "key_mv_prefix", "zone_mv", "migrate")
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

    it "includes the restructure tools" do
      names = described_class.all.map { |t| t[:name] }
      expect(names).to include("key_mv_prefix", "key_delete_prefix",
                               "zone_mv", "rule_lint", "migrate")
    end
  end
end
