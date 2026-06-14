require "spec_helper"

RSpec.describe Textus::Dispatch::Actions::KeyDeletePrefix do
  include_context "textus_store_fixture"

  before do
    %w[data/working/notes schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: working, kind: canon }
      entries:
        - { key: working.notes, path: working/notes, lane: working, owner: human:self, kind: nested, nested: true }
    YAML
    File.write(File.join(root, "data/working/notes/a.md"), "---\n_meta: {name: a, uid: aaaaaaaaaaaaaaaa}\n---\nA\n")
    File.write(File.join(root, "data/working/notes/b.md"), "---\n_meta: {name: b, uid: bbbbbbbbbbbbbbbb}\n---\nB\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }

  def build_key_delete_prefix
    call_value = Textus::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    lambda do |prefix, dry_run: false|
      described_class.new(prefix: prefix, dry_run: dry_run).call(container: store.container, call: call_value)
    end
  end

  it "previews keys to delete without touching files" do
    plan = build_key_delete_prefix.call(
      "working.notes", dry_run: true
    )
    expect(plan.steps.map { |s| s["key"] }).to contain_exactly("working.notes.a", "working.notes.b")
    expect(File.exist?(File.join(root, "data/working/notes/a.md"))).to be(true)
  end

  it "deletes when dry_run: false" do
    build_key_delete_prefix.call(
      "working.notes", dry_run: false
    )
    expect(Dir.glob(File.join(root, "data/working/notes/*.md"))).to be_empty
  end

  it "prunes the now-empty parent directory after the last leaf is deleted (F3)" do
    build_key_delete_prefix.call("working.notes", dry_run: false)
    expect(File.directory?(File.join(root, "data/working/notes"))).to be(false)
    expect(File.directory?(File.join(root, "data/working"))).to be(true)
  end
end
