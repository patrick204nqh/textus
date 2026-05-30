require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Manifest intake:" do
  include_context "textus_store_fixture"

  before { FileUtils.mkdir_p(root) }

  def write_manifest(yaml)
    File.write(File.join(root, "manifest.yaml"), yaml)
  end

  def load_manifest(yaml)
    write_manifest(yaml)
    Textus::Manifest.load(root)
  end

  def load_entry(yaml)
    load_manifest(yaml).data.entries.first
  end

  it "parses intake.handler and intake.config" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: working, kind: quarantine }]
      entries:
        - key: working.news
          kind: intake
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
            config: { url: https://example.com/feed }
    YAML
    expect(e).to be_a(Textus::Manifest::Entry::Intake)
    expect(e.handler).to eq("news_handler")
    expect(e.config).to eq({ "url" => "https://example.com/feed" })
  end

  it "exposes fetch rule via Manifest#rules_for(key)" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: working, kind: quarantine }]
      entries:
        - key: working.news
          kind: intake
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
      rules:
        - match: working.news
          fetch:
            ttl: 10m
            on_stale: timed_sync
            sync_budget_ms: 800
    YAML
    set = m.rules.for("working.news")
    expect(set.fetch).to be_a(Textus::Domain::Policy::Fetch)
    expect(set.fetch.ttl_seconds).to eq(600)
    expect(set.fetch.on_stale).to eq(:timed_sync)
    expect(set.fetch.sync_budget_ms).to eq(800)
  end

  it "returns an empty RuleSet for keys with no matching fetch rule" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: working, kind: origin }]
      entries:
        - { key: working.x, path: working/x.md, zone: working, kind: leaf}

    YAML
    expect(m.rules.for("working.x").fetch).to be_nil
  end

  it "defaults to a Leaf entry when no intake block is present" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: working, kind: origin }]
      entries:
        - { key: working.x, path: working/x.md, zone: working, kind: leaf}

    YAML
    expect(e).to be_a(Textus::Manifest::Entry::Leaf)
    expect(e).not_to be_intake
  end

  it "parses intake.publish_to as a list of targets" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: working, kind: quarantine }]
      entries:
        - key: working.news
          kind: intake
          path: working/news.md
          zone: working
          publish_to: [NEWS.md, docs/news.md]
          intake:
            handler: news_handler
    YAML
    expect(e.publish_to).to eq(["NEWS.md", "docs/news.md"])
  end

  it "defaults publish_to to an empty array when omitted" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: working, kind: quarantine }]
      entries:
        - key: working.news
          kind: intake
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
    YAML
    expect(e.publish_to).to eq([])
  end
end
