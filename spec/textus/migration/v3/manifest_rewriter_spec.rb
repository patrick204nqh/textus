require "spec_helper"
require "yaml"

RSpec.describe Textus::Migration::V3::ManifestRewriter do
  let(:input) do
    <<~Y
      version: textus/2
      zones:
        - { name: identity, writable_by: [human],          readable_by: all }
        - { name: working,  writable_by: [human, ai, script], readable_by: all }
        - { name: inbox,    writable_by: [script],         readable_by: all }
        - { name: review,   writable_by: [ai, human],      readable_by: all }
        - { name: output,   writable_by: [build],          readable_by: all }
      entries:
        - key: inbox.calendar
          zone: inbox
          path: calendar.md
          format: markdown
          intake: { handler: ical-events, config: { url: "x" } }
          owner: script:cron
        - key: output.marketplace
          zone: output
          path: marketplace.json
          format: json
          projection:
            select: [working.skills]
            pluck: [name]
            reduce: marketplace_indexer
          publish_to: [.claude-plugin/marketplace.json]
          owner: textus:build
      policies:
        - match: "inbox.calendar.*"
          refresh: { ttl: 1h, on_stale: warn }
          handler_allowlist: [ical-events]
        - match: "review.**"
          promote_requires: [schema_valid, human_accept]
    Y
  end

  it "rewrites version to textus/3" do
    out = YAML.safe_load(described_class.rewrite(input))
    expect(out["version"]).to eq("textus/3")
  end

  it "renames writable_by→write_policy and adds read_policy" do
    out = YAML.safe_load(described_class.rewrite(input))
    out["zones"].each do |z|
      expect(z).to have_key("write_policy")
      expect(z).to have_key("read_policy")
      expect(z).not_to have_key("writable_by")
      expect(z).not_to have_key("readable_by")
    end
  end

  it "renames actors ai/script/build inside write_policy" do
    out = YAML.safe_load(described_class.rewrite(input))
    working = out["zones"].find { |z| z["name"] == "working" }
    expect(working["write_policy"]).to contain_exactly("human", "agent", "runner")
    output_zone = out["zones"].find { |z| z["name"] == "output" }
    expect(output_zone["write_policy"]).to contain_exactly("builder")
  end

  it "renames zone inbox→intake (name + key prefix + entry zone)" do
    out = YAML.safe_load(described_class.rewrite(input))
    names = out["zones"].map { |z| z["name"] }
    expect(names).to include("intake")
    expect(names).not_to include("inbox")
    cal = out["entries"].find { |e| e["zone"] == "intake" }
    expect(cal["key"]).to eq("intake.calendar")
  end

  it "renames projection: → compute: { kind: projection, transform: ... }" do
    out = YAML.safe_load(described_class.rewrite(input))
    mp = out["entries"].find { |e| e["key"] == "output.marketplace" }
    expect(mp).not_to have_key("projection")
    expect(mp["compute"]).to include("kind" => "projection", "transform" => "marketplace_indexer")
    expect(mp["compute"]).not_to have_key("reduce")
  end

  it "renames owner strings" do
    out = YAML.safe_load(described_class.rewrite(input))
    cal = out["entries"].find { |e| e["zone"] == "intake" }
    expect(cal["owner"]).to eq("runner:cron")
    mp = out["entries"].find { |e| e["key"] == "output.marketplace" }
    expect(mp["owner"]).to eq("textus:builder")
  end

  it "renames policies:→rules: and handler_allowlist:→intake_handler_allowlist:" do
    out = YAML.safe_load(described_class.rewrite(input))
    expect(out).not_to have_key("policies")
    cal_rule = out["rules"].find { |r| r["match"] == "intake.calendar.*" }
    expect(cal_rule).to have_key("intake_handler_allowlist")
    expect(cal_rule).not_to have_key("handler_allowlist")
  end

  it "rewrites match: globs (inbox→intake prefix)" do
    out = YAML.safe_load(described_class.rewrite(input))
    matches = out["rules"].map { |r| r["match"] }
    expect(matches).to include("intake.calendar.*")
    expect(matches).not_to include("inbox.calendar.*")
  end

  it "rewrites promote_requires: → promotion.requires" do
    out = YAML.safe_load(described_class.rewrite(input))
    review_rule = out["rules"].find { |r| r["match"] == "review.**" }
    expect(review_rule["promotion"]).to eq("requires" => %w[schema_valid human_accept])
    expect(review_rule).not_to have_key("promote_requires")
  end

  it "rewrites generator: → compute: { kind: external, ... }" do
    yaml = <<~Y
      version: textus/2
      zones:
        - { name: output, writable_by: [build] }
      entries:
        - key: output.big
          zone: output
          path: big.json
          format: json
          generator:
            command: rake build:big-index
            sources: [working.docs]
    Y
    out = YAML.safe_load(described_class.rewrite(yaml))
    e = out["entries"].first
    expect(e).not_to have_key("generator")
    expect(e["compute"]).to eq("kind" => "external", "command" => "rake build:big-index", "sources" => ["working.docs"])
  end

  it "is idempotent" do
    once = described_class.rewrite(input)
    twice = described_class.rewrite(once)
    expect(YAML.safe_load(once)).to eq(YAML.safe_load(twice))
  end

  it "leaves the intake handler config block untouched (no key inside it gets rewritten)" do
    out = YAML.safe_load(described_class.rewrite(input))
    cal = out["entries"].find { |e| e["zone"] == "intake" }
    expect(cal["intake"]).to eq("handler" => "ical-events", "config" => { "url" => "x" })
  end
end
