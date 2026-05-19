require "spec_helper"
require "fileutils"
require "tmpdir"
require "time"

RSpec.describe Textus::AuditLog do
  let(:tmp)  { Dir.mktmpdir("textus-audit") }
  let(:root) { File.join(tmp, ".textus") }
  let(:log)  { Textus::AuditLog.new(root) }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  it "appends a tab-separated line per write" do
    log.append(role: "human", verb: "put", key: "working.x",
               etag_before: nil, etag_after: "sha256:abc")
    line = File.read(File.join(root, "audit.log")).lines.first
    fields = line.chomp.split("\t")
    expect(fields.length).to eq(6)
    expect { Time.iso8601(fields[0]) }.not_to raise_error
    expect(fields[1..]).to eq(["human", "put", "working.x", "NULL", "sha256:abc"])
  end

  it "returns the most recent role that wrote a key" do
    log.append(role: "ai",    verb: "put", key: "working.x", etag_before: nil, etag_after: "a")
    log.append(role: "human", verb: "put", key: "working.x", etag_before: "a", etag_after: "b")
    log.append(role: "ai",    verb: "put", key: "working.y", etag_before: nil, etag_after: "c")
    expect(log.last_writer_for("working.x")).to eq("human")
    expect(log.last_writer_for("working.y")).to eq("ai")
    expect(log.last_writer_for("missing")).to be_nil
  end

  it "appends an event_error row with JSON extras in column 7" do
    log = Textus::AuditLog.new(root)
    log.append(role: "script", verb: "event_error", key: "working.x",
               etag_before: nil, etag_after: nil,
               extras: { "event" => "put", "hook" => "boom", "error" => "boom!" })
    cols = File.read(File.join(root, "audit.log")).chomp.split("\t")
    expect(cols.length).to eq(7)
    expect(JSON.parse(cols[6])).to include("event" => "put", "hook" => "boom")
  end

  it "writes 6-column lines for regular writes (back-compat)" do
    log = Textus::AuditLog.new(root)
    log.append(role: "human", verb: "put", key: "working.x",
               etag_before: nil, etag_after: "abc")
    cols = File.read(File.join(root, "audit.log")).chomp.split("\t")
    expect(cols.length).to eq(6)
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
    expect(lines.all? { |l| l.chomp.split("\t").length == 6 }).to be true
  end
end
