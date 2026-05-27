require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Reads::PolicyExplain do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

      rules:
        - match: "working.*"
          refresh: { ttl: 1h, on_stale: warn }
        - match: working.doc
          refresh: { ttl: 5m, on_stale: sync }
          intake_handler_allowlist: [src_a, src_b]
        - match: "**"
          promotion:
            requires: [schema_valid]
    YAML
    Textus::Store.new(textus)
  end

  it "lists every matching block with per-slot presence flags" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = Textus::Operations.for(store, role: "human")
      result = ops.policy_explain(key: "working.doc")

      expect(result[:key]).to eq("working.doc")
      expect(result[:matched_blocks].length).to eq(3)
      matches = result[:matched_blocks].map { |b| b[:match] }
      expect(matches).to contain_exactly("working.*", "working.doc", "**")
    end
  end

  it "surfaces the per-slot effective winner (most-specific match)" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = Textus::Operations.for(store, role: "human")
      result = ops.policy_explain(key: "working.doc")

      expect(result[:effective][:refresh][:ttl_seconds]).to eq(300)
      expect(result[:effective][:refresh][:on_stale]).to eq(:sync)
      expect(result[:effective][:handler_allowlist]).to eq(%w[src_a src_b])
      expect(result[:effective][:promotion]).to eq({ requires: [:schema_valid] })
    end
  end

  it "returns nil-valued effective slots when no policy matches" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, runner] }
        entries:
          - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

      YAML
      store = Textus::Store.new(textus)
      ops = Textus::Operations.for(store, role: "human")
      result = ops.policy_explain(key: "working.doc")
      expect(result[:matched_blocks]).to eq([])
      expect(result[:effective][:refresh]).to be_nil
      expect(result[:effective][:handler_allowlist]).to be_nil
      expect(result[:effective][:promotion]).to be_nil
    end
  end
end
