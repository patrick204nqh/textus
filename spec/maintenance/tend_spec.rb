require "spec_helper"

RSpec.describe Textus::Maintenance::Tend do
  it "is registered as a dispatcher verb and a RoleScope method" do
    expect(Textus::Dispatcher::VERBS).to include(:tend)
    expect(Textus::Dispatcher::VERBS[:tend]).to eq(described_class)
    expect(Textus::RoleScope.instance_methods).to include(:tend)
  end

  it "declares a contract surfaced on both CLI and MCP" do
    spec = described_class.contract
    expect(spec.verb).to eq(:tend)
    expect(spec.cli?).to be(true)
    expect(spec.mcp?).to be(true)
  end

  describe "#call apply path" do
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
            retention: { expire_after: 30d }
      YAML

      leaf = File.join(root, "zones/review/oncall.md")
      File.write(leaf, "# oncall notes\n")
      aged = Time.now - (40 * 86_400)
      File.utime(aged, aged, leaf)

      FileUtils.mkdir_p(audit_dir_path(root))
      File.write(audit_log_path(root), "")
    end

    let(:store) { Textus::Store.new(root) }
    let(:ctx)   { test_ctx(role: "human") }

    def build_tend
      call_value = Textus::Call.new(
        role: ctx.role, correlation_id: ctx.correlation_id,
        now: ctx.now, dry_run: ctx.dry_run
      )
      described_class.new(container: store.container, call: call_value)
    end

    it "expires the aged leaf, reports health, and aggregates sub-results" do
      leaf = File.join(root, "zones/review/oncall.md")
      result = build_tend.call

      expect(result["ok"]).to be(true)
      expect(result["dry_run"]).to be(false)
      expect(result["retain"]["expired"]).to include("review.oncall")
      expect(result).to have_key("fetch")
      expect(result).to have_key("health")
      expect(File.exist?(leaf)).to be(false)
    end
  end
end
