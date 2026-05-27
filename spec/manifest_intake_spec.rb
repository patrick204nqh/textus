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
    load_manifest(yaml).entries.first
  end

  it "parses intake.handler and intake.config" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [runner] }]
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

  it "exposes refresh rule via Manifest#rules_for(key)" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [runner] }]
      entries:
        - key: working.news
          kind: intake
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
      rules:
        - match: working.news
          refresh:
            ttl: 10m
            on_stale: timed_sync
            sync_budget_ms: 800
    YAML
    set = m.rules_for("working.news")
    expect(set.refresh).to be_a(Textus::Domain::Policy::Refresh)
    expect(set.refresh.ttl_seconds).to eq(600)
    expect(set.refresh.on_stale).to eq(:timed_sync)
    expect(set.refresh.sync_budget_ms).to eq(800)
  end

  it "returns an empty RuleSet for keys with no matching refresh rule" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working, kind: leaf}

    YAML
    expect(m.rules_for("working.x").refresh).to be_nil
  end

  it "defaults to a Leaf entry when no intake block is present" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working, kind: leaf}

    YAML
    expect(e).to be_a(Textus::Manifest::Entry::Leaf)
    expect(e).not_to be_intake
  end
end
