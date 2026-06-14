require "spec_helper"

RSpec.describe Textus::Dispatch::Actions::RuleExplain do
  include_context "textus_store_fixture"

  # `knowledge.doc` is a canon leaf; retention (drop/archive) is valid for any
  # stored (non-derived) entry, so a leaf can carry a retention rule (ADR 0093).
  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: data/knowledge/doc.md, lane: knowledge, kind: leaf}

      rules:
        - match: "knowledge.*"
          retention: { ttl: 1h, action: archive }
          react:
            on: [entry.written]
            do: materialize
        - match: knowledge.doc
          retention: { ttl: 5m, action: drop }
          handler_permit: [src_a, src_b]
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
    it "returns only the effective {retention, guard} winners" do
      result = store.as("human").rule_explain("knowledge.doc")
      expect(result).to be_a(Hash)
      expect(result.keys - %w[retention guard react]).to be_empty
      expect(result["retention"]["ttl_seconds"]).to eq(300)
      expect(result["retention"]["action"]).to eq(:drop)
      expect(result["react"]).to eq({ "on" => ["entry.written"], "do" => "materialize" })
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

      expect(result[:effective][:retention][:ttl_seconds]).to eq(300)
      expect(result[:effective][:retention][:action]).to eq(:drop)
      expect(result[:effective][:handler_permit]).to eq(%w[src_a src_b])
      expect(result[:effective][:react]).to eq({ "on" => ["entry.written"], "do" => "materialize" })
    end

    it "surfaces a retention rule in matched_blocks and effective (ADR 0093)" do
      # An intake entry in a machine zone can carry a retention (age-GC) rule.
      ret_store = store_from_manifest(root, lanes: %w[artifacts knowledge], manifest: <<~YAML)
        version: textus/3
        roles: [{ name: automation, can: [converge] }, { name: human, can: [author] }]
        lanes:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - { key: knowledge.src, path: data/knowledge/src.md, lane: knowledge, kind: leaf }
          - { key: artifacts.feed, path: data/artifacts/feed.md, lane: artifacts,
              kind: produced, source: { from: fetch, handler: noop } }
        rules:
          - match: artifacts.feed
            retention: { ttl: 30d, action: archive }
      YAML
      result = ret_store.as("human").rule_explain("artifacts.feed", detail: true)
      expect(result[:matched_blocks].first[:retention]).to be(true)
      expect(result[:effective][:retention][:action]).to eq(:archive)
    end

    it "reports the effective guard predicate names per transition" do
      result = store.as("human").rule_explain("knowledge.doc", detail: true)
      expect(result[:guards][:put][:floor]).to eq(["lane_writable_by"])
      expect(result[:guards][:put][:rule]).to eq([])
      expect(result[:guards][:accept][:floor]).to include("author_held", "target_is_canon")
      expect(result[:guards][:accept][:rule]).to include("schema_valid")
    end

    it "returns nil-valued effective slots when no policy matches" do
      no_policy_store = store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: data/knowledge/doc.md, lane: knowledge, kind: leaf}

      YAML
      result = no_policy_store.as("human").rule_explain("knowledge.doc", detail: true)
      expect(result[:matched_blocks]).to eq([])
      expect(result[:effective][:retention]).to be_nil
      expect(result[:effective][:handler_permit]).to be_nil
      expect(result[:guards][:put][:floor]).to eq(["lane_writable_by"])
      expect(result[:guards][:put][:rule]).to eq([])
    end
  end
end
