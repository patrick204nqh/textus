require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Restructure::KeyDeletePrefix do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/working/notes schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.notes, path: working/notes, zone: working, schema: null, owner: human:self, kind: nested, nested: true }
    YAML
    File.write(File.join(root, "zones/working/notes/a.md"), "---\n_meta: {name: a, uid: aaaaaaaaaaaaaaaa}\n---\nA\n")
    File.write(File.join(root, "zones/working/notes/b.md"), "---\n_meta: {name: b, uid: bbbbbbbbbbbbbbbb}\n---\nB\n")
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }
  let(:ports) { Textus::Application::Ports.from_store(store) }
  let(:ops) { Textus::Operations.for(store, role: ctx.role) }

  it "previews keys to delete without touching files" do
    plan = described_class.new(ctx: ctx, ports: ports, operations: ops).call(
      prefix: "working.notes", dry_run: true,
    )
    expect(plan.steps.map { |s| s["key"] }).to contain_exactly("working.notes.a", "working.notes.b")
    expect(File.exist?(File.join(root, "zones/working/notes/a.md"))).to be(true)
  end

  it "deletes when dry_run: false" do
    described_class.new(ctx: ctx, ports: ports, operations: ops).call(
      prefix: "working.notes", dry_run: false,
    )
    expect(Dir.glob(File.join(root, "zones/working/notes/*.md"))).to be_empty
  end
end
