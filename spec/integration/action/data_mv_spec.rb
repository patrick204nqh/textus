require "spec_helper"

RSpec.describe Textus::Action::DataMv do
  include_context "textus_store_fixture"

  before do
    %w[data/scratch schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: scratch, kind: canon }
      entries:
        - { key: scratch.note, path: scratch/note.md, lane: scratch, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "data/scratch/note.md"), "---\n_meta: {name: note, uid: nnnnnnnnnnnnnnnn}\n---\nN\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }

  def build_data_mv
    call_value = Textus::Value::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    lambda do |from, to, dry_run: false|
      described_class.new(from: from, to: to, dry_run: dry_run).call(container: store.container, call: call_value)
    end
  end

  it "previews data-lane rename + key relocation + manifest rewrite" do
    plan = build_data_mv.call("scratch", "sandbox", dry_run: true)
    ops = plan.steps.map { |s| s["op"] }
    expect(ops).to include("rename_zone", "mv")
    expect(File.exist?(File.join(root, "data/scratch/note.md"))).to be(true)
  end

  it "refuses rename if destination data lane already exists" do
    FileUtils.mkdir_p(File.join(root, "data/sandbox"))
    File.write(File.join(root, "data/sandbox/.keep"), "")
    expect do
      build_data_mv.call("scratch", "sandbox", dry_run: true)
    end.to raise_error(Textus::UsageError, /already exists/)
  end

  it "applies the rename and rewrites manifest" do
    build_data_mv.call("scratch", "sandbox", dry_run: false)
    raw = YAML.safe_load_file(File.join(root, "manifest.yaml"))
    lane_names = raw["lanes"].map { |z| z["name"] }
    expect(lane_names).to include("sandbox")
    expect(lane_names).not_to include("scratch")
    expect(File.exist?(File.join(root, "data/sandbox/note.md"))).to be(true)
  end
end
