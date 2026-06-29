require "spec_helper"
require "time"

RSpec.describe Textus::Port::AuditLog do
  let(:tmp)  { Dir.mktmpdir("textus-audit") }
  let(:root) { File.join(tmp, ".textus") }
  let(:log)  { Textus::Port::AuditLog.new(root) }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "appends one NDJSON object per write" do
    log.append(role: "human", verb: "put", key: "working.x",
               etag_before: nil, etag_after: "sha256:abc")
    line = File.read(audit_log_path(root)).lines.first
    parsed = JSON.parse(line)
    expect { Time.iso8601(parsed["ts"]) }.not_to raise_error
    expect(parsed).to include(
      "role" => "human", "verb" => "put", "key" => "working.x",
      "etag_before" => nil, "etag_after" => "sha256:abc"
    )
  end

  it "returns the most recent role that wrote a key" do
    log.append(role: "agent", verb: "put", key: "working.x", etag_before: nil, etag_after: "a")
    log.append(role: "human", verb: "put", key: "working.x", etag_before: "a", etag_after: "b")
    log.append(role: "agent", verb: "put", key: "working.y", etag_before: nil, etag_after: "c")
    expect(log.last_writer_for("working.x")).to eq("human")
    expect(log.last_writer_for("working.y")).to eq("agent")
    expect(log.last_writer_for("missing")).to be_nil
  end

  it "appends an event_error row with extras sub-object" do
    log.append(role: "automation", verb: "event_error", key: "working.x",
               etag_before: nil, etag_after: nil,
               extras: { "event" => "put", "hook" => "boom", "error" => "boom!" })
    parsed = JSON.parse(File.read(audit_log_path(root)).lines.first)
    expect(parsed["extras"]).to include("event" => "put", "hook" => "boom")
  end

  it "omits extras key for regular writes" do
    log.append(role: "human", verb: "put", key: "working.x",
               etag_before: nil, etag_after: "abc")
    parsed = JSON.parse(File.read(audit_log_path(root)).lines.first)
    expect(parsed).not_to have_key("extras")
  end

  it "is safe under concurrent writes (smoke test)" do
    threads = 20.times.map do |i|
      Thread.new do
        log.append(role: "agent", verb: "put", key: "working.k#{i}",
                   etag_before: nil, etag_after: "sha256:#{i}")
      end
    end
    threads.each(&:join)
    lines = File.read(audit_log_path(root)).lines
    expect(lines.length).to eq(20)
    expect(lines.all? { |l| l.start_with?("{") }).to be true
    expect(lines.all? { |l| JSON.parse(l)["verb"] == "put" }).to be true
  end

  describe "#verify_integrity" do
    it "returns empty array for a missing log file" do
      expect(log.verify_integrity).to eq([])
    end

    it "returns empty array for a log of well-formed NDJSON rows" do
      log.append(role: "human", verb: "put", key: "working.x",
                 etag_before: nil, etag_after: "sha256:abc")
      log.append(role: "agent", verb: "put", key: "working.y",
                 etag_before: nil, etag_after: "sha256:def")
      expect(log.verify_integrity).to eq([])
    end

    it "flags a malformed JSON line with reason=invalid_json" do
      log.append(role: "human", verb: "put", key: "working.x",
                 etag_before: nil, etag_after: "sha256:abc")
      File.open(audit_log_path(root), "a") { |f| f.puts "{not json" }
      issues = log.verify_integrity
      expect(issues).to contain_exactly(hash_including("lineno" => 2, "reason" => "invalid_json"))
    end

    it "detects a seq gap (missing row)" do
      FileUtils.mkdir_p(Textus::Store::Layout.new(root).audit_dir_path)
      path = Textus::Store::Layout.new(root).audit_log_path
      File.open(path, "a") do |f|
        row = { "seq" => 1, "ts" => "2026-01-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "k.x", "etag_before" => nil,
                "etag_after" => "abc" }
        f.puts(JSON.generate(row))
        row["seq"] = 3
        f.puts(JSON.generate(row))
      end
      violations = log.verify_integrity
      expect(violations.length).to eq(1)
      expect(violations.first["reason"]).to eq("seq_gap")
      expect(violations.first["detail"]).to include("expected 2, got 3")
    end

    it "detects a seq regression (row out of order or overwritten)" do
      FileUtils.mkdir_p(Textus::Store::Layout.new(root).audit_dir_path)
      path = Textus::Store::Layout.new(root).audit_log_path
      File.open(path, "a") do |f|
        row = { "seq" => 1, "ts" => "2026-01-01T00:00:00Z", "role" => "human", "verb" => "put", "key" => "k.x", "etag_before" => nil,
                "etag_after" => "abc" }
        f.puts(JSON.generate(row))
        row["seq"] = 2
        f.puts(JSON.generate(row))
        row["seq"] = 1
        f.puts(JSON.generate(row))
      end
      violations = log.verify_integrity
      expect(violations.length).to eq(1)
      expect(violations.first["reason"]).to eq("seq_gap")
      expect(violations.first["detail"]).to include("expected 3, got 1")
    end

    it "skips empty lines silently" do
      FileUtils.mkdir_p(Textus::Store::Layout.new(root).audit_dir_path)
      File.write(audit_log_path(root), "\n\n")
      expect(log.verify_integrity).to eq([])
    end

    it "flags non-JSON lines as invalid_json" do
      FileUtils.mkdir_p(Textus::Store::Layout.new(root).audit_dir_path)
      File.write(audit_log_path(root), "not json\n")
      issues = log.verify_integrity
      expect(issues).to contain_exactly(hash_including("lineno" => 1, "reason" => "invalid_json"))
    end
  end

  describe "textus/4 role canonicalization" do
    it "writes canonical role names verbatim for new rows" do
      log.append(role: "agent", verb: "put", key: "working.x",
                 etag_before: nil, etag_after: "sha256:0")
      row = JSON.parse(File.read(audit_log_path(root)).lines.last)
      expect(row["role"]).to eq("agent")
    end

    it "tolerates pre-0.11.0 legacy role values (ai/script/build) verbatim" do
      # Audit history can contain legacy role values from before the textus/4
      # vocabulary rename. The reader returns them verbatim — anyone reading
      # historical rows is responsible for normalization. New writes always use
      # canonical roles.
      FileUtils.mkdir_p(Textus::Store::Layout.new(root).audit_dir_path)
      File.write(
        Textus::Store::Layout.new(root).audit_log_path,
        JSON.generate("ts" => "2026-01-01T00:00:00Z", "role" => "ai",
                      "verb" => "put", "key" => "working.x",
                      "etag_before" => nil, "etag_after" => "sha256:0") + "\n",
      )
      log = described_class.new(root)
      expect(log.last_writer_for("working.x")).to eq("ai")
    end
  end
end
