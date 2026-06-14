require "spec_helper"
require "time"

RSpec.describe Textus::Dispatch::Actions::Audit do
  include_context "textus_store_fixture"

  let!(:store) do
    store_from_manifest(root,
                        lanes: %w[knowledge identity],
                        manifest: <<~YAML)
                          version: textus/3
                          lanes:
                            - { name: knowledge, kind: canon }
                            - { name: identity,   kind: canon }
                          entries:
                            - { key: knowledge.doc, path: data/knowledge/doc.md, lane: knowledge, kind: leaf}

                            - { key: identity.note,  path: identity/note.md,  lane: identity, kind: leaf}

                        YAML
  end

  def write_log(rows)
    FileUtils.mkdir_p(audit_dir_path(root))
    File.open(audit_log_path(root), "w") do |f|
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
    ops = store.as("human")
    expect(ops.audit).to eq([])
  end

  it "filters audit rows by key" do
    write_log([
                { "ts" => "2026-05-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "knowledge.doc" },
                { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "identity.note" },
                { "ts" => "2026-05-03T00:00:00Z", "role" => "ai",    "verb" => "put", "key" => "knowledge.doc" },
              ])
    ops = store.as("human")
    rows = ops.audit(key: "knowledge.doc")
    expect(rows.length).to eq(2)
    expect(rows.map { |r| r["key"] }).to all(eq("knowledge.doc"))
  end

  it "filters by correlation_id (nested under extras)" do
    cid = "abc-123"
    write_log([
                { "ts" => "2026-05-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "knowledge.doc",
                  "extras" => { "correlation_id" => cid } },
                { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "identity.note",
                  "extras" => { "correlation_id" => "other" } },
                { "ts" => "2026-05-03T00:00:00Z", "role" => "ai",    "verb" => "put", "key" => "knowledge.doc",
                  "extras" => { "correlation_id" => cid } },
              ])
    ops = store.as("human")
    rows = ops.audit(correlation_id: cid)
    expect(rows.length).to eq(2)
    expect(rows.map { |r| r["key"] }).to contain_exactly("knowledge.doc", "knowledge.doc")
  end

  it "filters by zone via manifest lookup" do
    write_log([
                { "ts" => "2026-05-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "knowledge.doc" },
                { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "identity.note" },
              ])
    ops = store.as("human")
    rows = ops.audit(lane: "identity")
    expect(rows.map { |r| r["key"] }).to eq(["identity.note"])
  end

  it "filters by since" do
    write_log([
                { "ts" => "2026-04-30T00:00:00Z", "role" => "human", "verb" => "put", "key" => "knowledge.doc" },
                { "ts" => "2026-05-02T00:00:00Z", "role" => "human", "verb" => "put", "key" => "knowledge.doc" },
              ])
    ops = store.as("human")
    rows = ops.audit(since: Time.parse("2026-05-01T00:00:00Z"))
    expect(rows.map { |r| r["ts"] }).to eq(["2026-05-02T00:00:00Z"])
  end

  it "honors limit" do
    rows = (1..5).map do |i|
      { "ts" => "2026-05-0#{i}T00:00:00Z", "role" => "human", "verb" => "put", "key" => "knowledge.doc" }
    end
    write_log(rows)
    ops = store.as("human")
    out = ops.audit(limit: 2)
    expect(out.length).to eq(2)
  end
end
