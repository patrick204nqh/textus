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

  it "is safe under concurrent writes (smoke test)" do
    threads = 20.times.map do |i|
      Thread.new { log.append(role: "ai", verb: "put", key: "working.k#{i}",
                              etag_before: nil, etag_after: "sha256:#{i}") }
    end
    threads.each(&:join)
    lines = File.read(File.join(root, "audit.log")).lines
    expect(lines.length).to eq(20)
    expect(lines.all? { |l| l.chomp.split("\t").length == 6 }).to be true
  end
end
