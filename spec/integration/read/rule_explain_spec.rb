require "spec_helper"

RSpec.describe Textus::Read::RuleExplain do
  include_context "textus_store_fixture"

  # `knowledge.doc` is a canon leaf; `warn` is valid for any stored (non-intake,
  # non-derived) entry. Using a `warn` action avoids requiring an intake kind here.
  let(:store) do
    store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

      rules:
        - match: "knowledge.*"
          upkeep: { ttl: 1h, action: warn }
        - match: knowledge.doc
          upkeep: { ttl: 5m, action: warn }
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
      # ADR 0091: keyed grammar — no `on:` discriminator in rendered output
      expect(result["upkeep"]).not_to have_key("on")
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

      # ADR 0091: keyed grammar — no `on:` discriminator in rendered output
      expect(result[:effective][:upkeep]).not_to have_key(:on)
      expect(result[:effective][:upkeep][:ttl_seconds]).to eq(300)
      expect(result[:effective][:upkeep][:action]).to eq(:warn)
      expect(result[:effective][:handler_allowlist]).to eq(%w[src_a src_b])
    end

    it "surfaces source_change upkeep in matched_blocks and effective (ADR 0091)" do
      # A derived entry in a machine zone accepts strategy grammar
      mat_store = store_from_manifest(root, zones: %w[artifacts knowledge], manifest: <<~YAML)
        version: textus/3
        roles: [{ name: automation, can: [reconcile] }, { name: human, can: [author] }]
        zones:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - { key: knowledge.src, path: knowledge/src.md, zone: knowledge, kind: leaf }
          - { key: artifacts.out, path: artifacts/out.json, zone: artifacts,
              kind: derived, format: json, compute: { kind: projection, select: ["knowledge.*"] } }
        rules:
          - match: artifacts.out
            upkeep: { strategy: sync }
      YAML
      result = mat_store.as("human").rule_explain("artifacts.out", detail: true)
      expect(result[:matched_blocks].first[:upkeep]).to be(true)
      # ADR 0091: keyed grammar — strategy rendered without `on:` prefix
      expect(result[:effective][:upkeep]).to eq({ strategy: "sync" })
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
