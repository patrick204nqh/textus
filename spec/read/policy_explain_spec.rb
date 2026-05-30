require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Read::PolicyExplain do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: origin }
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
    Textus::Store.new(textus)
  end

  it "lists every matching block with per-slot presence flags" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      result = ops.policy_explain(key: "working.doc")

      expect(result[:key]).to eq("working.doc")
      expect(result[:matched_blocks].length).to eq(4)
      matches = result[:matched_blocks].map { |b| b[:match] }
      expect(matches).to contain_exactly("working.*", "working.doc", "**", "working.doc")
    end
  end

  it "surfaces the per-slot effective winner (most-specific match)" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      result = ops.policy_explain(key: "working.doc")

      expect(result[:effective][:fetch][:ttl_seconds]).to eq(300)
      expect(result[:effective][:fetch][:on_stale]).to eq(:sync)
      expect(result[:effective][:handler_allowlist]).to eq(%w[src_a src_b])
    end
  end

  it "reports the effective guard predicate names per transition" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      result = store.as("human").policy_explain(key: "working.doc")
      expect(result[:guards][:put]).to eq(["zone_writable_by"])
      expect(result[:guards][:accept]).to include("accept_signed", "schema_valid")
    end
  end

  it "reports retention windows in the matched blocks and effective output" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      result = store.as("human").policy_explain(key: "working.doc")
      expect(result[:effective][:retention]).to eq(expire_after: 2_592_000, archive_after: nil)
      expect(result[:matched_blocks].any? { |b| b[:retention] }).to be(true)
    end
  end

  it "returns nil-valued effective slots when no policy matches" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, kind: origin }
        entries:
          - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

      YAML
      store = Textus::Store.new(textus)
      ops = store.as("human")
      result = ops.policy_explain(key: "working.doc")
      expect(result[:matched_blocks]).to eq([])
      expect(result[:effective][:fetch]).to be_nil
      expect(result[:effective][:handler_allowlist]).to be_nil
      expect(result[:guards][:put]).to eq(["zone_writable_by"])
    end
  end
end
