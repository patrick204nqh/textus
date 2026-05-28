require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Restructure::RuleLint do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/intake schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, write_policy: [runner] }
      entries:
        - { key: intake.feed, path: intake/feed.md, zone: intake, schema: null, owner: runner:self, kind: intake, intake: { handler: noop } }
      rules:
        - { match: "intake.*", refresh: { ttl: 600, on_stale: warn } }
    YAML
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx) { test_ctx(role: "human") }

  it "returns ok: true and zero diff lines when candidate is identical" do
    result = described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store)).call(
      candidate_yaml: File.read(File.join(root, "manifest.yaml")),
    )
    expect(result.steps).to eq([])
    expect(result.warnings).to eq([])
  end

  it "reports an added rule" do
    candidate = File.read(File.join(root, "manifest.yaml")) +
                %(  - { match: "intake.other", refresh: { ttl: 60, on_stale: error } }\n)
    result = described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store)).call(candidate_yaml: candidate)
    adds = result.steps.select { |s| s["op"] == "add_rule" }
    expect(adds.size).to eq(1)
  end

  it "errors on an invalid candidate" do
    expect do
      described_class.new(ctx: ctx, ports: Textus::Application::Ports.from_store(store)).call(candidate_yaml: "this is not yaml: : :")
    end.to raise_error(Textus::Error)
  end
end
