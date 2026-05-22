require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Manifest intake:" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) }

  def write_manifest(yaml)
    File.write(File.join(root, "manifest.yaml"), yaml)
  end

  def load_entry(yaml)
    write_manifest(yaml)
    Textus::Manifest.load(root).entries.first
  end

  it "parses intake.handler, intake.config, intake.ttl, intake.on_stale, intake.sync_budget_ms" do
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
            ttl: 10m
            on_stale: timed_sync
            sync_budget_ms: 800
    YAML
    expect(e.intake_handler).to eq("news_handler")
    expect(e.intake_config).to eq({ "url" => "https://example.com/feed" })
    expect(e.ttl).to eq("10m")
    expect(e.on_stale).to eq(:timed_sync)
    expect(e.sync_budget_ms).to eq(800)
  end

  it "defaults on_stale to :warn when omitted" do
    e = load_entry(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
    YAML
    expect(e.on_stale).to eq(:warn)
  end

  it "defaults sync_budget_ms to 500 when omitted" do
    e = load_entry(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
    YAML
    expect(e.sync_budget_ms).to eq(500)
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
    expect(e.ttl).to be_nil
    expect(e.on_stale).to eq(:warn)
    expect(e.sync_budget_ms).to eq(500)
  end

  it "rejects legacy source: block with UsageError matching /renamed to intake/" do
    write_manifest(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          source: { handler: news_handler }
    YAML
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /renamed to 'intake:' in 0\.9/)
  end

  it "rejects intake.fetch (legacy key) with UsageError matching /renamed to intake.handler/" do
    write_manifest(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          intake: { fetch: news_handler }
    YAML
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /source\.fetch renamed to intake\.handler in 0\.9/)
  end

  it "rejects unknown on_stale values with UsageError matching /on_stale must be one of/" do
    write_manifest(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
            on_stale: explode
    YAML
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /on_stale must be one of/)
  end

  it "accepts on_stale: sync" do
    e = load_entry(<<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [script] }]
      entries:
        - key: working.news
          path: working/news.md
          zone: working
          intake:
            handler: news_handler
            on_stale: sync
    YAML
    expect(e.on_stale).to eq(:sync)
  end
end
