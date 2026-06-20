require "spec_helper"

RSpec.describe Textus::Action::RuleLint do
  include_context "textus_store_fixture"

  before do
    %w[data/intake schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: intake, kind: machine }
      entries:
        - { key: intake.feed, path: intake/feed.md, lane: intake, owner: automation:self, kind: produced, source: { from: external, command: "make", sources: [] } }
      rules:
        - { match: "intake.*", retention: { ttl: 600, action: drop } }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }

  def build_rule_lint
    call_value = Textus::Value::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    lambda do |candidate_yaml:|
      described_class.new(candidate_yaml: candidate_yaml).call(container: store.container, call: call_value)
    end
  end

  it "returns ok: true and zero diff lines when candidate is identical" do
    result = build_rule_lint.call(
      candidate_yaml: File.read(File.join(root, "manifest.yaml")),
    )
    expect(result.steps).to eq([])
    expect(result.warnings).to eq([])
  end

  it "reports an added rule" do
    candidate = File.read(File.join(root, "manifest.yaml")) +
                %(  - { match: "intake.other", retention: { ttl: 60, action: drop } }\n)
    result = build_rule_lint.call(candidate_yaml: candidate)
    adds = result.steps.select { |s| s["op"] == "add_rule" }
    expect(adds.size).to eq(1)
  end

  it "errors on an invalid candidate" do
    expect do
      build_rule_lint.call(candidate_yaml: "this is not yaml: : :")
    end.to raise_error(Textus::Error)
  end
end
