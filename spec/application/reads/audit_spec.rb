require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "time"

RSpec.describe Textus::Application::Reads::Audit do
  def build_store(root)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "zones", "identity"))
    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
        - { name: identity,   write_policy: [human] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

        - { key: identity.note,  path: identity/note.md,  zone: identity, kind: leaf}

    YAML
    Textus::Store.new(textus)
  end

  def write_log(root, rows)
    File.open(File.join(root, ".textus", "audit.log"), "w") do |f|
      rows.each { |r| f.puts(JSON.generate(r)) }
    end
  end

  describe ".parse_since" do
    it "parses 7d as a relative offset from now" do
      expect(described_class.parse_since("7d", now: Time.utc(2026, 5, 22)))
        .to eq(Time.utc(2026, 5, 15))
    end

    it "parses ISO8601 dates" do
      expect(described_class.parse_since("2026-01-15", now: Time.utc(2026, 5, 22)))
        .to eq(Time.parse("2026-01-15"))
    end

    it "returns nil for garbage input" do
      expect(described_class.parse_since("nope")).to be_nil
    end
  end

  it "returns [] when audit.log does not exist" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      ops = store.session(role: "human")
      expect(ops.audit).to eq([])
    end
  end

  it "filters audit rows by key" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      write_log(root, [
                  { "ts" => "2026-05-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "working.doc" },
                  { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "identity.note" },
                  { "ts" => "2026-05-03T00:00:00Z", "role" => "ai",    "verb" => "put", "key" => "working.doc" },
                ])
      ops = store.session(role: "human")
      rows = ops.audit(key: "working.doc")
      expect(rows.length).to eq(2)
      expect(rows.map { |r| r["key"] }).to all(eq("working.doc"))
    end
  end

  it "filters by correlation_id (nested under extras)" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      cid = "abc-123"
      write_log(root, [
                  { "ts" => "2026-05-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "working.doc",
                    "extras" => { "correlation_id" => cid } },
                  { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "identity.note",
                    "extras" => { "correlation_id" => "other" } },
                  { "ts" => "2026-05-03T00:00:00Z", "role" => "ai",    "verb" => "put", "key" => "working.doc",
                    "extras" => { "correlation_id" => cid } },
                ])
      ops = store.session(role: "human")
      rows = ops.audit(correlation_id: cid)
      expect(rows.length).to eq(2)
      expect(rows.map { |r| r["key"] }).to contain_exactly("working.doc", "working.doc")
    end
  end

  it "filters by zone via manifest lookup" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      write_log(root, [
                  { "ts" => "2026-05-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "working.doc" },
                  { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "identity.note" },
                ])
      ops = store.session(role: "human")
      rows = ops.audit(zone: "identity")
      expect(rows.map { |r| r["key"] }).to eq(["identity.note"])
    end
  end

  it "filters by since" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      write_log(root, [
                  { "ts" => "2026-04-30T00:00:00Z", "role" => "human", "verb" => "put", "key" => "working.doc" },
                  { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "working.doc" },
                ])
      ops = store.session(role: "human")
      rows = ops.audit(since: Time.parse("2026-05-01T00:00:00Z"))
      expect(rows.map { |r| r["ts"] }).to eq(["2026-05-02T00:00:00Z"])
    end
  end

  it "honors limit" do
    Dir.mktmpdir do |root|
      store = build_store(root)
      rows = (1..5).map do |i|
        { "ts" => "2026-05-0#{i}T00:00:00Z", "role" => "human", "verb" => "put", "key" => "working.doc" }
      end
      write_log(root, rows)
      ops = store.session(role: "human")
      out = ops.audit(limit: 2)
      expect(out.length).to eq(2)
    end
  end
end
