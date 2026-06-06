require "spec_helper"

RSpec.describe Textus::Read::Freshness do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[review], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: review, kind: canon }
      entries:
        - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
      rules:
        - match: "review.*"
          upkeep: { "on": stale, ttl: 30d, action: drop }
    YAML
  end

  let(:leaf) { File.join(root, "zones/review/oncall.md") }

  before do
    store
    File.write(leaf, "# oncall\n")
    aged = Time.now - (40 * 86_400)
    File.utime(aged, aged, leaf)
  end

  def report = described_class.new(container: store.container, call: test_ctx(role: "human")).call

  it "reports an aged entry with status expired and its on_expire action" do
    row = report.find { |r| r[:key] == "review.oncall" }
    expect(row[:status]).to eq(:expired)
    expect(row[:action]).to eq(:drop)
  end
end
