require "spec_helper"

RSpec.describe Textus::Doctor::Check::LifecycleActionInvalid do
  include_context "textus_store_fixture"

  def write_manifest(rules_yaml)
    store_from_manifest(root, zones: %w[feeds review], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: quarantine }
        - { name: review, kind: canon }
      entries:
        - { key: feeds.cal, path: feeds/cal.json, zone: feeds, kind: intake, intake: { handler: test_intake } }
        - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
      rules:
      #{rules_yaml}
    YAML
  end

  def issues
    described_class.new(Textus::Store.new(root).container).call
  end

  it "flags refresh on a non-intake (stored) entry" do
    write_manifest('  - { match: "review.*", upkeep: { "on": stale, ttl: 1h, action: refresh } }')
    codes = issues.map { |i| i["code"] }
    expect(codes).to include("lifecycle.action_invalid")
  end

  it "flags drop on an intake entry" do
    write_manifest('  - { match: "feeds.*", upkeep: { "on": stale, ttl: 1h, action: drop } }')
    expect(issues.map { |i| i["code"] }).to include("lifecycle.action_invalid")
  end

  it "passes a valid pairing (refresh on intake, drop on stored)" do
    write_manifest(<<~RULES)
      - { match: "feeds.*", upkeep: { "on": stale, ttl: 1h, action: refresh } }
      - { match: "review.*", upkeep: { "on": stale, ttl: 30d, action: drop } }
    RULES
    expect(issues).to be_empty
  end
end
