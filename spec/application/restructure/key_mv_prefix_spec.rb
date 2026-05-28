require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Restructure::KeyMvPrefix do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/working/old zones/working/new schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent] }
      entries:
        - { key: working.old, path: working/old, zone: working, schema: null, owner: human:self, kind: nested, nested: true }
        - { key: working.new, path: working/new, zone: working, schema: null, owner: human:self, kind: nested, nested: true }
    YAML
    FileUtils.mkdir_p(File.join(root, "zones/working/old"))
    File.write(File.join(root, "zones/working/old/a.md"), "---\n_meta: {name: a, uid: aaaaaaaaaaaaaaaa}\n---\nbody-a\n")
    File.write(File.join(root, "zones/working/old/b.md"), "---\n_meta: {name: b, uid: bbbbbbbbbbbbbbbb}\n---\nbody-b\n")
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }
  let(:ports) { Textus::Application::Ports.from_store(store) }
  let(:ops) { Textus::Operations.for(store, role: ctx.role) }

  it "previews a bulk rename without touching files when dry_run" do
    plan = described_class.new(ctx: ctx, ports: ports, operations: ops).call(
      from_prefix: "working.old", to_prefix: "working.new", dry_run: true,
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
    described_class.new(ctx: ctx, ports: ports, operations: ops).call(
      from_prefix: "working.old", to_prefix: "working.new", dry_run: false,
    )
    expect(File.exist?(File.join(root, "zones/working/old/a.md"))).to be(false)
    expect(File.exist?(File.join(root, "zones/working/new/a.md"))).to be(true)
  end
end
