require "spec_helper"
require "tmpdir"
require "fileutils"
require "time"

RSpec.describe Textus::Read::Freshness do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "zones", "identity"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
        - { name: identity,   kind: canon }
      entries:
        - { key: working.doc,   path: working/doc.md,   zone: working, kind: leaf}

        - { key: working.stale, path: working/stale.md, zone: working, kind: leaf}

        - { key: identity.note,    path: identity/note.md,    zone: identity, kind: leaf}

      rules:
        - match: working.doc
          fetch: { ttl: 1h, on_stale: warn }
        - match: working.stale
          fetch: { ttl: 1s, on_stale: warn }
    YAML

    File.write(File.join(textus, "hooks", "noop.rb"), "")

    Textus::Store.new(textus)
  end

  def write_envelope(root, rel, last_fetched_at:)
    path = File.join(root, ".textus", "zones", rel)
    File.write(path, <<~MD)
      ---
      name: doc
      last_fetched_at: "#{last_fetched_at}"
      ---
      body
    MD
  end

  it "returns one row per manifest entry with :status, :key, :zone" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      write_envelope(root, "working/doc.md",   last_fetched_at: Time.now.utc.iso8601)
      write_envelope(root, "working/stale.md", last_fetched_at: (Time.now.utc - 3600).iso8601)

      ops = store.as("human")
      rows = ops.freshness

      keys = rows.map { |r| r[:key] }
      expect(keys).to contain_exactly("working.doc", "working.stale", "identity.note")

      expect(rows).to all(include(:status, :key, :zone))

      by_key = rows.to_h { |r| [r[:key], r] }
      expect(by_key["working.doc"][:status]).to eq(:fresh)
      expect(by_key["working.stale"][:status]).to eq(:stale)
      expect(by_key["identity.note"][:status]).to eq(:no_policy)
    end
  end

  it "filters by zone" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      rows = ops.freshness(zone: "identity")

      expect(rows.map { |r| r[:key] }).to eq(["identity.note"])
    end
  end

  it "filters by prefix" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      rows = ops.freshness(prefix: "working")

      expect(rows.map { |r| r[:key] }).to contain_exactly("working.doc", "working.stale")
    end
  end

  it "reports :never_fetched when policy exists but envelope is absent" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.as("human")
      rows = ops.freshness(prefix: "working.doc")
      expect(rows.first[:status]).to eq(:never_fetched)
      expect(rows.first[:next_due_at]).to be_nil
    end
  end

  it "computes :next_due_at as last_fetched_at + ttl when both are present" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      t = Time.utc(2026, 1, 1, 12, 0, 0)
      write_envelope(root, "working/doc.md", last_fetched_at: t.iso8601)
      ops = store.as("human")
      rows = ops.freshness(prefix: "working.doc")
      expect(Time.parse(rows.first[:next_due_at])).to eq(t + 3600)
    end
  end
end
