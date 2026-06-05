require "spec_helper"

RSpec.describe Textus::Maintenance::Reconcile do
  it "is registered as a dispatcher verb and a RoleScope method" do
    expect(Textus::Dispatcher::VERBS).to include(:reconcile)
    expect(Textus::Dispatcher::VERBS[:reconcile]).to eq(described_class)
    expect(Textus::RoleScope.instance_methods).to include(:reconcile)
  end

  it "declares a contract surfaced on both CLI and MCP" do
    spec = described_class.contract
    expect(spec.verb).to eq(:reconcile)
    expect(spec.cli?).to be(true)
    expect(spec.mcp?).to be(true)
  end

  describe "#call lifecycle sweep" do
    include_context "textus_store_fixture"

    before do
      FileUtils.mkdir_p(File.join(root, "zones/review"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: review, kind: canon }
        entries:
          - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
        rules:
          - match: "review.*"
            lifecycle: { ttl: 30d, on_expire: drop }
      YAML
      leaf = File.join(root, "zones/review/oncall.md")
      File.write(leaf, "---\n_meta: {name: oncall, uid: aaaaaaaaaaaaaaaa}\n---\nbody\n")
      aged = Time.now - (40 * 86_400)
      File.utime(aged, aged, leaf)
      FileUtils.mkdir_p(audit_dir_path(root))
      File.write(audit_log_path(root), "")
    end

    let(:store) { Textus::Store.new(root) }

    def build_reconcile
      cv = Textus::Call.new(role: "human", correlation_id: "t", now: Time.now, dry_run: false)
      described_class.new(container: store.container, call: cv)
    end

    it "drops an aged drop-policy entry and reports it" do
      leaf = File.join(root, "zones/review/oncall.md")
      result = build_reconcile.call
      expect(result["ok"]).to be(true)
      expect(result["dropped"]).to include("review.oncall")
      expect(File.exist?(leaf)).to be(false)
    end

    it "dry-run previews would_drop without deleting" do
      leaf = File.join(root, "zones/review/oncall.md")
      result = build_reconcile.call(dry_run: true)
      expect(result["dry_run"]).to be(true)
      expect(result["would_drop"]).to include("review.oncall")
      expect(File.exist?(leaf)).to be(true)
    end

    it "scopes by prefix (non-matching prefix is a no-op)" do
      leaf = File.join(root, "zones/review/oncall.md")
      result = build_reconcile.call(prefix: "nonexistent")
      expect(result["dropped"]).to be_empty
      expect(File.exist?(leaf)).to be(true)
    end
  end
end
