require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Boot do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, kind: accept_authority }
        - { name: agent, kind: proposer }
      zones:
        - { name: working, write_policy: [human] }
        - { name: review,  write_policy: [agent] }
      entries: []
    YAML
  end

  describe ".run / agent_quickstart" do
    it "exposes agent_quickstart with read_verbs, write_verbs, writable_zones, propose_zone, latest_seq" do
      out = described_class.build(container: Textus::Store.new(root).container)
      qs = out["agent_quickstart"]
      expect(qs).to be_a(Hash)
      expect(qs["read_verbs"]).to include("boot", "get", "list", "audit", "pulse", "freshness", "doctor")
      expect(qs["write_verbs"]).to include(a_string_matching(/put.*--as=agent/))
      expect(qs["writable_zones"]).to include("review")
      expect(qs["propose_zone"]).to eq("review")
      expect(qs).to have_key("latest_seq")
      expect(qs["latest_seq"]).to be_a(Integer)
    end

    it "includes pulse in the cli_verbs list" do
      out = described_class.build(container: Textus::Store.new(root).container)
      names = out["cli_verbs"].map { |v| v["name"] }
      expect(names).to include("pulse")
    end

    it "handles manifests with no proposer role gracefully" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: human, kind: accept_authority }
        zones:
          - { name: working, write_policy: [human] }
        entries: []
      YAML
      out = described_class.build(container: Textus::Store.new(root).container)
      qs = out["agent_quickstart"]
      expect(qs["write_verbs"]).to eq([])
      expect(qs["writable_zones"]).to eq([])
      expect(qs["propose_zone"]).to be_nil
    end
  end
end
