require "spec_helper"

RSpec.describe Textus::Maintenance::Migrate do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/working/old zones/working/new schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.old, path: working/old, zone: working, schema: null, owner: human:self, kind: nested, nested: true }
        - { key: working.new, path: working/new, zone: working, schema: null, owner: human:self, kind: nested, nested: true }
    YAML
    File.write(File.join(root, "zones/working/old/a.md"), "---\n_meta: {name: a, uid: aaaaaaaaaaaaaaaa}\n---\nA\n")
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }

  def build_migrate
    container = store.container
    call_value = Textus::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    described_class.new(
      container: container, call: call_value,
    )
  end

  it "runs a multi-op migration plan and returns combined Plan" do
    plan_yaml = <<~YAML
      version: 1
      operations:
        - { op: key_mv_prefix, from_prefix: working.old, to_prefix: working.new }
    YAML
    plan = build_migrate.call(plan_yaml: plan_yaml, dry_run: false)
    expect(plan.steps.map { |s| s["op"] }).to include("mv")
    expect(File.exist?(File.join(root, "zones/working/new/a.md"))).to be(true)
  end

  it "previews when dry_run: true without touching files" do
    plan_yaml = <<~YAML
      version: 1
      operations:
        - { op: key_mv_prefix, from_prefix: working.old, to_prefix: working.new }
    YAML
    build_migrate.call(plan_yaml: plan_yaml, dry_run: true)
    expect(File.exist?(File.join(root, "zones/working/old/a.md"))).to be(true)
  end

  it "raises on unknown op" do
    expect do
      build_migrate.call(
        plan_yaml: "version: 1\noperations:\n  - { op: bogus }\n", dry_run: true,
      )
    end.to raise_error(Textus::Error, /unknown op/)
  end
end
