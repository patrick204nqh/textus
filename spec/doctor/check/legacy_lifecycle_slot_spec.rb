require "spec_helper"

RSpec.describe Textus::Doctor::Check::LegacyLifecycleSlot do
  include_context "textus_store_fixture"

  def write_manifest(rules_yaml)
    store_from_manifest(root, zones: %w[review], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: review, kind: canon }
      entries:
        - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
      rules:
      #{rules_yaml}
    YAML
  end

  def issues
    described_class.new(Textus::Store.new(root).container).call
  end

  it "warns when a legacy retention: slot is present" do
    write_manifest('  - { match: "review.*", retention: { expire_after: 30d } }')
    issue = issues.find { |i| i["code"] == "lifecycle.legacy_slot" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("warning")
    expect(issue["fix"]).to match(/lifecycle migrate/)
  end

  it "is silent when only lifecycle: is used" do
    write_manifest('  - { match: "review.*", lifecycle: { ttl: 30d, on_expire: drop } }')
    expect(issues.map { |i| i["code"] }).not_to include("lifecycle.legacy_slot")
  end
end
