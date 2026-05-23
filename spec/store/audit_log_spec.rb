require "spec_helper"
require "fileutils"
require "tmpdir"
require "time"
require "json"

RSpec.describe Textus::Store::AuditLog do
  let(:tmp)  { Dir.mktmpdir("textus-audit") }
  let(:root) { File.join(tmp, ".textus") }
  let(:log)  { Textus::Store::AuditLog.new(root) }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "appends one NDJSON object per write" do
    log.append(role: "human", verb: "put", key: "working.x",
               etag_before: nil, etag_after: "sha256:abc")
    line = File.read(File.join(root, "audit.log")).lines.first
    parsed = JSON.parse(line)
    expect { Time.iso8601(parsed["ts"]) }.not_to raise_error
    expect(parsed).to include(
      "role" => "human", "verb" => "put", "key" => "working.x",
      "etag_before" => nil, "etag_after" => "sha256:abc"
    )
  end

  it "returns the most recent role that wrote a key" do
    log.append(role: "ai",    verb: "put", key: "working.x", etag_before: nil, etag_after: "a")
    log.append(role: "human", verb: "put", key: "working.x", etag_before: "a", etag_after: "b")
    log.append(role: "ai",    verb: "put", key: "working.y", etag_before: nil, etag_after: "c")
    expect(log.last_writer_for("working.x")).to eq("human")
    expect(log.last_writer_for("working.y")).to eq("ai")
    expect(log.last_writer_for("missing")).to be_nil
  end

  it "appends an event_error row with extras sub-object" do
    log.append(role: "script", verb: "event_error", key: "working.x",
               etag_before: nil, etag_after: nil,
               extras: { "event" => "put", "hook" => "boom", "error" => "boom!" })
    parsed = JSON.parse(File.read(File.join(root, "audit.log")).lines.first)
    expect(parsed["extras"]).to include("event" => "put", "hook" => "boom")
  end

  it "omits extras key for regular writes" do
    log.append(role: "human", verb: "put", key: "working.x",
               etag_before: nil, etag_after: "abc")
    parsed = JSON.parse(File.read(File.join(root, "audit.log")).lines.first)
    expect(parsed).not_to have_key("extras")
  end

  it "is safe under concurrent writes (smoke test)" do
    threads = 20.times.map do |i|
      Thread.new do
        log.append(role: "ai", verb: "put", key: "working.k#{i}",
                   etag_before: nil, etag_after: "sha256:#{i}")
      end
    end
    threads.each(&:join)
    lines = File.read(File.join(root, "audit.log")).lines
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
      log.append(role: "ai", verb: "put", key: "working.y",
                 etag_before: nil, etag_after: "sha256:def")
      expect(log.verify_integrity).to eq([])
    end

    it "flags a malformed JSON line with reason=invalid_json" do
      log.append(role: "human", verb: "put", key: "working.x",
                 etag_before: nil, etag_after: "sha256:abc")
      File.open(File.join(root, "audit.log"), "a") { |f| f.puts "{not json" }
      issues = log.verify_integrity
      expect(issues).to contain_exactly(hash_including("lineno" => 2, "reason" => "invalid_json"))
    end

    it "skips empty lines silently" do
      File.write(File.join(root, "audit.log"), "\n\n")
      expect(log.verify_integrity).to eq([])
    end

    it "flags non-JSON lines as invalid_json" do
      File.write(File.join(root, "audit.log"), "not json\n")
      issues = log.verify_integrity
      expect(issues).to contain_exactly(hash_including("lineno" => 1, "reason" => "invalid_json"))
    end
  end
end
