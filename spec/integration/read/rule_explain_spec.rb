require "spec_helper"

RSpec.describe Textus::Read::RuleExplain do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

      rules:
        - match: "knowledge.*"
          upkeep: { "on": stale, ttl: 1h, action: refresh }
        - match: knowledge.doc
          upkeep: { "on": stale, ttl: 5m, action: refresh }
          intake_handler_allowlist: [src_a, src_b]
        - match: "**"
          guard:
            accept: [schema_valid]
    YAML
  end

  describe "contract (ADR 0059: one verb, both depths)" do
    it "is the rule_explain verb, MCP-surfaced, with key + detail args" do
      expect(described_class.contract.verb).to eq(:rule_explain)
      expect(described_class.contract.mcp?).to be(true)
      expect(described_class.contract.args.map(&:name)).to eq(%i[key detail])
    end
  end

  describe "lean (default) — the agent-cheap effective read" do
    it "returns only the effective {lifecycle, guard} winners" do
      result = store.as("human").rule_explain("knowledge.doc")
      expect(result).to be_a(Hash)
      expect(result.keys - %w[upkeep guard]).to be_empty
      expect(result["upkeep"]["on"]).to eq("stale")
      expect(result["upkeep"]["ttl_seconds"]).to eq(300)
    end
  end

  describe "detail: true — the verbose explanation" do
    it "lists every matching block with per-slot presence flags" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)

      expect(result[:key]).to eq("knowledge.doc")
      expect(result[:matched_blocks].length).to eq(3)
      matches = result[:matched_blocks].map { |b| b[:match] }
      expect(matches).to contain_exactly("knowledge.*", "knowledge.doc", "**")
    end

    it "surfaces the per-slot effective winner (most-specific match)" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)

      expect(result[:effective][:upkeep][:on]).to eq("stale")
      expect(result[:effective][:upkeep][:ttl_seconds]).to eq(300)
      expect(result[:effective][:upkeep][:action]).to eq(:refresh)
      expect(result[:effective][:handler_allowlist]).to eq(%w[src_a src_b])
    end

    it "surfaces source_change upkeep in matched_blocks and effective (ADR 0090)" do
      mat_store = store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}
        rules:
          - match: knowledge.doc
            upkeep: { "on": source_change, strategy: sync }
      YAML
      result = mat_store.as("human").rule_explain("knowledge.doc", detail: true)
      expect(result[:matched_blocks].first[:upkeep]).to be(true)
      expect(result[:effective][:upkeep]).to eq({ on: "source_change", strategy: "sync" })
    end

    it "reports the effective guard predicate names per transition" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)
      expect(result[:guards][:put]).to eq(["zone_writable_by"])
      expect(result[:guards][:accept]).to include("author_held", "schema_valid")
    end

    it "returns nil-valued effective slots when no policy matches" do
      no_policy_store = store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

      YAML
      result = no_policy_store.as("human").rule_explain("knowledge.doc", detail: true)
      expect(result[:matched_blocks]).to eq([])
      expect(result[:effective][:upkeep]).to be_nil
      expect(result[:effective][:handler_allowlist]).to be_nil
      expect(result[:guards][:put]).to eq(["zone_writable_by"])
    end
  end
end
