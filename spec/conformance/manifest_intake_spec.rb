require "spec_helper"

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
      zones: [{ name: feeds, kind: quarantine }]
      entries:
        - key: feeds.news
          kind: intake
          path: feeds/news.md
          zone: feeds
          intake:
            handler: news_handler
            config: { url: https://example.com/feed }
    YAML
    expect(e).to be_a(Textus::Manifest::Entry::Intake)
    expect(e.handler).to eq("news_handler")
    expect(e.config).to eq({ "url" => "https://example.com/feed" })
  end

  it "exposes lifecycle rule via Manifest#rules_for(key)" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: quarantine }]
      entries:
        - key: feeds.news
          kind: intake
          path: feeds/news.md
          zone: feeds
          intake:
            handler: news_handler
      rules:
        - match: feeds.news
          lifecycle:
            ttl: 10m
            on_expire: refresh
            budget_ms: 800
    YAML
    set = m.rules.for("feeds.news")
    expect(set.lifecycle).to be_a(Textus::Domain::Policy::Lifecycle)
    expect(set.lifecycle.ttl_seconds).to eq(600)
    expect(set.lifecycle.on_expire).to eq(:refresh)
    expect(set.lifecycle.budget_ms).to eq(800)
  end

  it "returns an empty RuleSet for keys with no matching lifecycle rule" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries:
        - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf}

    YAML
    expect(m.rules.for("knowledge.x").lifecycle).to be_nil
  end

  it "defaults to a Leaf entry when no intake block is present" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries:
        - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf}

    YAML
    expect(e).to be_a(Textus::Manifest::Entry::Leaf)
    expect(e).not_to be_intake
  end

  it "parses intake.publish_to as a list of targets" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: quarantine }]
      entries:
        - key: feeds.news
          kind: intake
          path: feeds/news.md
          zone: feeds
          publish:
            to: [NEWS.md, docs/news.md]
          intake:
            handler: news_handler
    YAML
    expect(e.publish_to).to eq(["NEWS.md", "docs/news.md"])
  end

  it "defaults publish_to to an empty array when omitted" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: quarantine }]
      entries:
        - key: feeds.news
          kind: intake
          path: feeds/news.md
          zone: feeds
          intake:
            handler: news_handler
    YAML
    expect(e.publish_to).to eq([])
  end
end
