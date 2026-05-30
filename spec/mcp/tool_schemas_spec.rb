require "spec_helper"

RSpec.describe Textus::MCP::ToolSchemas do
  describe ".all" do
    it "returns one entry per tool, each with name/description/inputSchema" do
      tools = described_class.all
      names = tools.map { |t| t[:name] }
      expect(names).to include("boot", "tick", "find", "read", "write",
                               "propose", "fetch", "fetch_stale",
                               "schema", "rules")
      tools.each do |t|
        expect(t).to include(:name, :description, :inputSchema)
        expect(t[:inputSchema][:type]).to eq("object")
      end
    end

    it "marks key-required tools' inputSchema with required: ['key']" do
      read = described_class.all.find { |t| t[:name] == "read" }
      expect(read[:inputSchema][:required]).to eq(["key"])
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
