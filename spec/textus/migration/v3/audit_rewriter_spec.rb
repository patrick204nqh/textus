require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe Textus::Migration::V3::AuditRewriter do
  let(:tmpdir) { Dir.mktmpdir }
  let(:log_path) { File.join(tmpdir, ".textus/audit.log") }

  after { FileUtils.rm_rf(tmpdir) }

  def parse_line(line)
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end

  def marker_rows
    File.readlines(log_path).filter_map { |line| parse_line(line) }
                            .select { |r| r["verb"] == described_class::MARKER_VERB }
  end

  it "appends exactly one marker row on first run" do
    described_class.run(root: tmpdir)
    expect(marker_rows.length).to eq(1)
  end

  it "does not append a second marker on re-run (idempotent)" do
    described_class.run(root: tmpdir)
    described_class.run(root: tmpdir)
    expect(marker_rows.length).to eq(1)
  end

  it "writes role=builder and verb=migration-marker" do
    described_class.run(root: tmpdir)
    row = marker_rows.first
    expect(row["role"]).to eq("builder")
    expect(row["verb"]).to eq("migration-marker")
  end

  it "sets key and etag fields to nil" do
    described_class.run(root: tmpdir)
    row = marker_rows.first
    expect(row).to have_key("key")
    expect(row["key"]).to be_nil
    expect(row["etag_before"]).to be_nil
    expect(row["etag_after"]).to be_nil
  end

  it "records from_protocol and to_protocol in details" do
    described_class.run(root: tmpdir)
    row = marker_rows.first
    expect(row["details"]["from_protocol"]).to eq("textus/2")
    expect(row["details"]["to_protocol"]).to eq("textus/3")
  end

  it "writes a parseable ISO8601 timestamp" do
    described_class.run(root: tmpdir)
    row = marker_rows.first
    expect { Time.parse(row["ts"]) }.not_to raise_error
  end

  it "creates the log file if it does not exist yet" do
    expect(File.exist?(log_path)).to be false
    described_class.run(root: tmpdir)
    expect(File.exist?(log_path)).to be true
  end

  it "appends to an existing log (does not truncate)" do
    FileUtils.mkdir_p(File.dirname(log_path))
    File.write(log_path, JSON.generate("ts" => "2025-01-01T00:00:00Z",
                                       "role" => "human",
                                       "verb" => "put",
                                       "key" => "intake.doc",
                                       "etag_before" => nil,
                                       "etag_after" => "abc") + "\n")
    described_class.run(root: tmpdir)
    lines = File.readlines(log_path).filter_map { |l| parse_line(l) }
    expect(lines.length).to eq(2)
    expect(lines.first["verb"]).to eq("put")
  end
end
