require "spec_helper"

RSpec.describe "Manifest intake source: + retention:" do
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

  it "parses source.handler and source.config (intake)" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - key: feeds.news
          kind: produced
          path: feeds/news.md
          zone: feeds
          source:
            from: handler
            handler: news_handler
            config: { url: https://example.com/feed }
    YAML
    expect(e).to be_a(Textus::Manifest::Entry::Produced)
    expect(e.intake?).to be(true)
    expect(e.handler).to eq("news_handler")
    expect(e.config).to eq({ "url" => "https://example.com/feed" })
  end

  it "carries the re-pull cadence on source.ttl" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - key: feeds.news
          kind: produced
          path: feeds/news.md
          zone: feeds
          source:
            from: handler
            handler: news_handler
            ttl: 10m
    YAML
    expect(e.source.ttl_seconds).to eq(600)
  end

  it "exposes a retention rule via Manifest#rules.for(key)" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - key: feeds.news
          kind: produced
          path: feeds/news.md
          zone: feeds
          source:
            from: handler
            handler: news_handler
      rules:
        - match: feeds.news
          retention:
            ttl: 10m
            action: archive
    YAML
    set = m.rules.for("feeds.news")
    expect(set.retention).to be_a(Textus::Domain::Policy::Retention)
    expect(set.retention.ttl_seconds).to eq(600)
    expect(set.retention.action).to eq(:archive)
  end

  it "returns an empty RuleSet for keys with no matching retention rule" do
    m = load_manifest(<<~YAML)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries:
        - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf}

    YAML
    expect(m.rules.for("knowledge.x").retention).to be_nil
  end

  it "defaults to a Leaf entry when no source block is present" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries:
        - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf}

    YAML
    expect(e).to be_a(Textus::Manifest::Entry::Leaf)
    expect(e).not_to be_intake
  end

  it "parses publish.to as a list of targets" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - key: feeds.news
          kind: produced
          path: feeds/news.md
          zone: feeds
          publish:
            - { to: NEWS.md }
            - { to: docs/news.md }
          source:
            from: handler
            handler: news_handler
    YAML
    expect(e.publish_to).to eq(["NEWS.md", "docs/news.md"])
  end

  it "defaults publish_to to an empty array when omitted" do
    e = load_entry(<<~YAML)
      version: textus/3
      zones: [{ name: feeds, kind: machine }]
      entries:
        - key: feeds.news
          kind: produced
          path: feeds/news.md
          zone: feeds
          source:
            from: handler
            handler: news_handler
    YAML
    expect(e.publish_to).to eq([])
  end
end
