require "spec_helper"
require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe Textus::Application::Restructure::ZoneMv do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/scratch schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: scratch, write_policy: [human] }
      entries:
        - { key: scratch.note, path: scratch/note.md, zone: scratch, schema: null, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "zones/scratch/note.md"), "---\n_meta: {name: note, uid: nnnnnnnnnnnnnnnn}\n---\nN\n")
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }

  it "previews zone rename + key relocation + manifest rewrite" do
    plan = described_class.new(ctx: ctx, caps: Textus::Application.caps_from_store(store)[1]).call(from: "scratch", to: "sandbox",
                                                                                                   dry_run: true)
    ops = plan.steps.map { |s| s["op"] }
    expect(ops).to include("rename_zone", "mv")
    expect(File.exist?(File.join(root, "zones/scratch/note.md"))).to be(true)
  end

  it "refuses rename if destination zone already exists" do
    FileUtils.mkdir_p(File.join(root, "zones/sandbox"))
    File.write(File.join(root, "zones/sandbox/.keep"), "")
    expect do
      described_class.new(ctx: ctx, caps: Textus::Application.caps_from_store(store)[1]).call(from: "scratch", to: "sandbox", dry_run: true)
    end.to raise_error(Textus::UsageError, /already exists/)
  end

  it "applies the rename and rewrites manifest" do
    described_class.new(ctx: ctx, caps: Textus::Application.caps_from_store(store)[1]).call(from: "scratch", to: "sandbox", dry_run: false)
    raw = YAML.safe_load_file(File.join(root, "manifest.yaml"))
    zone_names = raw["zones"].map { |z| z["name"] }
    expect(zone_names).to include("sandbox")
    expect(zone_names).not_to include("scratch")
    expect(File.exist?(File.join(root, "zones/sandbox/note.md"))).to be(true)
  end
end
