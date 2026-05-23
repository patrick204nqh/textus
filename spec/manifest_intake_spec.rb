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
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
            config: { url: https://example.com/feed }
    YAML
    expect(e.intake_handler).to eq("news_handler")
    expect(e.intake_config).to eq({ "url" => "https://example.com/feed" })
  end

  it "exposes refresh policy via Manifest#policies_for(key)" do
    m = load_manifest(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
      policies:
        - match: working.news
          refresh:
            ttl: 10m
            on_stale: timed_sync
            sync_budget_ms: 800
    YAML
    set = m.policies_for("working.news")
    expect(set.refresh).to be_a(Textus::Domain::Policy::Refresh)
    expect(set.refresh.ttl_seconds).to eq(600)
    expect(set.refresh.on_stale).to eq(:timed_sync)
    expect(set.refresh.sync_budget_ms).to eq(800)
  end

  it "returns an empty PolicySet for keys with no matching refresh policy" do
    m = load_manifest(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    expect(m.policies_for("working.x").refresh).to be_nil
  end

  it "defaults intake_config to {} when no intake block is present" do
    e = load_entry(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    expect(e.intake_handler).to be_nil
    expect(e.intake_config).to eq({})
  end
end
