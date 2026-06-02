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
          fetch: { ttl: 1h, on_stale: warn }
        - match: knowledge.doc
          fetch: { ttl: 5m, on_stale: sync }
          intake_handler_allowlist: [src_a, src_b]
        - match: "**"
          guard:
            accept: [schema_valid]
        - match: knowledge.doc
          retention: { expire_after: 30d }
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
    it "returns only the effective {fetch, guard} winners" do
      result = store.as("human").rule_explain("knowledge.doc")
      expect(result).to be_a(Hash)
      expect(result.keys - %w[fetch guard]).to be_empty
      expect(result["fetch"]["ttl_seconds"]).to eq(300)
    end
  end

  describe "detail: true — the verbose explanation" do
    it "lists every matching block with per-slot presence flags" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)

      expect(result[:key]).to eq("knowledge.doc")
      expect(result[:matched_blocks].length).to eq(4)
      matches = result[:matched_blocks].map { |b| b[:match] }
      expect(matches).to contain_exactly("knowledge.*", "knowledge.doc", "**", "knowledge.doc")
    end

    it "surfaces the per-slot effective winner (most-specific match)" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)

      expect(result[:effective][:fetch][:ttl_seconds]).to eq(300)
      expect(result[:effective][:fetch][:on_stale]).to eq(:sync)
      expect(result[:effective][:handler_allowlist]).to eq(%w[src_a src_b])
    end

    it "reports the effective guard predicate names per transition" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)
      expect(result[:guards][:put]).to eq(["zone_writable_by"])
      expect(result[:guards][:accept]).to include("author_held", "schema_valid")
    end

    it "reports retention windows in the matched blocks and effective output" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)
      expect(result[:effective][:retention]).to eq(expire_after: 2_592_000, archive_after: nil)
      expect(result[:matched_blocks].any? { |b| b[:retention] }).to be(true)
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
      expect(result[:effective][:fetch]).to be_nil
      expect(result[:effective][:handler_allowlist]).to be_nil
      expect(result[:guards][:put]).to eq(["zone_writable_by"])
    end
  end
end
