require "spec_helper"

RSpec.describe Textus::Maintenance::KeyMvPrefix do
  include_context "textus_store_fixture"

  before do
    %w[zones/working/old zones/working/new schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.old, path: working/old, zone: working, owner: human:self, kind: nested, nested: true }
        - { key: working.new, path: working/new, zone: working, owner: human:self, kind: nested, nested: true }
    YAML
    FileUtils.mkdir_p(File.join(root, "zones/working/old"))
    File.write(File.join(root, "zones/working/old/a.md"), "---\n_meta: {name: a, uid: aaaaaaaaaaaaaaaa}\n---\nbody-a\n")
    File.write(File.join(root, "zones/working/old/b.md"), "---\n_meta: {name: b, uid: bbbbbbbbbbbbbbbb}\n---\nbody-b\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }

  def build_key_mv_prefix
    container = store.container
    call_value = Textus::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    described_class.new(
      container: container, call: call_value,
    )
  end

  it "previews a bulk rename without touching files when dry_run" do
    plan = build_key_mv_prefix.call(
      "working.old", "working.new", dry_run: true
    )
    ops = plan.steps.map { |s| s["op"] }
    expect(ops).to all(eq("mv"))
    expect(plan.steps.map { |s| [s["from"], s["to"]] }).to contain_exactly(
      %w[working.old.a working.new.a],
      %w[working.old.b working.new.b],
    )
    expect(File.exist?(File.join(root, "zones/working/old/a.md"))).to be(true)
  end

  it "applies the rename when dry_run: false" do
    build_key_mv_prefix.call(
      "working.old", "working.new", dry_run: false
    )
    expect(File.exist?(File.join(root, "zones/working/old/a.md"))).to be(false)
    expect(File.exist?(File.join(root, "zones/working/new/a.md"))).to be(true)
  end

  it "prunes the now-empty source directory after moving every leaf out (F3)" do
    build_key_mv_prefix.call("working.old", "working.new", dry_run: false)
    expect(File.directory?(File.join(root, "zones/working/old"))).to be(false)
    expect(File.directory?(File.join(root, "zones/working"))).to be(true)
  end

  it "refuses when from_prefix is itself a leaf rather than building a malformed key" do
    expect do
      build_key_mv_prefix.call("working.old.a", "working.new.a", dry_run: true)
    end.to raise_error(Textus::UsageError, /itself a leaf — use `mv`/)
  end
end
