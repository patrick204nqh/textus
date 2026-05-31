require "spec_helper"

RSpec.describe Textus::Read::PolicyExplain do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[working], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

      rules:
        - match: "working.*"
          fetch: { ttl: 1h, on_stale: warn }
        - match: working.doc
          fetch: { ttl: 5m, on_stale: sync }
          intake_handler_allowlist: [src_a, src_b]
        - match: "**"
          guard:
            accept: [schema_valid]
        - match: working.doc
          retention: { expire_after: 30d }
    YAML
  end

  it "lists every matching block with per-slot presence flags" do
    ops = store.as("human")
    result = ops.policy_explain(key: "working.doc")

    expect(result[:key]).to eq("working.doc")
    expect(result[:matched_blocks].length).to eq(4)
    matches = result[:matched_blocks].map { |b| b[:match] }
    expect(matches).to contain_exactly("working.*", "working.doc", "**", "working.doc")
  end

  it "surfaces the per-slot effective winner (most-specific match)" do
    ops = store.as("human")
    result = ops.policy_explain(key: "working.doc")

    expect(result[:effective][:fetch][:ttl_seconds]).to eq(300)
    expect(result[:effective][:fetch][:on_stale]).to eq(:sync)
    expect(result[:effective][:handler_allowlist]).to eq(%w[src_a src_b])
  end

  it "reports the effective guard predicate names per transition" do
    result = store.as("human").policy_explain(key: "working.doc")
    expect(result[:guards][:put]).to eq(["zone_writable_by"])
    expect(result[:guards][:accept]).to include("author_held", "schema_valid")
  end

  it "reports retention windows in the matched blocks and effective output" do
    result = store.as("human").policy_explain(key: "working.doc")
    expect(result[:effective][:retention]).to eq(expire_after: 2_592_000, archive_after: nil)
    expect(result[:matched_blocks].any? { |b| b[:retention] }).to be(true)
  end

  it "returns nil-valued effective slots when no policy matches" do
    no_policy_store = store_from_manifest(root, zones: %w[working], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

    YAML
    ops = no_policy_store.as("human")
    result = ops.policy_explain(key: "working.doc")
    expect(result[:matched_blocks]).to eq([])
    expect(result[:effective][:fetch]).to be_nil
    expect(result[:effective][:handler_allowlist]).to be_nil
    expect(result[:guards][:put]).to eq(["zone_writable_by"])
  end
end
