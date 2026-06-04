require "spec_helper"

RSpec.describe Textus::Maintenance::LifecycleMigrate do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[feeds review], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: quarantine }
        - { name: review, kind: canon }
      entries:
        - { key: feeds.cal, path: feeds/cal.json, zone: feeds, kind: intake, intake: { handler: test_intake } }
        - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
      rules:
        - match: "feeds.*"
          fetch: { ttl: 1h, on_stale: sync }
        - match: "review.*"
          retention: { expire_after: 30d }
    YAML
  end

  def build
    described_class.new(container: store.container, call: test_ctx(role: "human"))
  end

  it "dry-run previews the rewrite without touching manifest.yaml" do
    store
    before_yaml = File.read(File.join(root, "manifest.yaml"))
    plan = build.call(dry_run: true)
    expect(plan.steps.map { |s| s["match"] }).to include("feeds.*", "review.*")
    expect(File.read(File.join(root, "manifest.yaml"))).to eq(before_yaml)
  end

  it "rewrites fetch+retention slots into lifecycle slots" do
    store
    build.call(dry_run: false)
    rules = YAML.safe_load_file(File.join(root, "manifest.yaml"))["rules"]
    feeds  = rules.find { |r| r["match"] == "feeds.*" }
    review = rules.find { |r| r["match"] == "review.*" }

    expect(feeds["lifecycle"]).to eq("ttl" => "1h", "on_expire" => "refresh")
    expect(feeds).not_to have_key("fetch")
    expect(review["lifecycle"]).to eq("ttl" => "30d", "on_expire" => "drop")
    expect(review).not_to have_key("retention")
  end
end
