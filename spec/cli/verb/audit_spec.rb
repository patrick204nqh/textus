require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"

RSpec.describe Textus::CLI::Verb::Audit do
  let(:tmp)    { Dir.mktmpdir }
  let(:root)   { File.join(tmp, ".textus") }
  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, script] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working }
    YAML
    File.open(File.join(root, "audit.log"), "w") do |f|
      f.puts JSON.generate({ "ts" => "2026-05-01T00:00:00Z", "role" => "human",
                             "verb" => "put", "key" => "working.doc",
                             "extras" => { "correlation_id" => "abc" } })
      f.puts JSON.generate({ "ts" => "2026-05-02T00:00:00Z", "role" => "ai",
                             "verb" => "put", "key" => "working.doc" })
    end
  end

  after { FileUtils.remove_entry(tmp) }

  it "emits all rows when called with no filters" do
    rc = run(["audit"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["verb"]).to eq("audit")
    expect(payload["rows"].length).to eq(2)
  end

  it "filters by --role" do
    rc = run(["audit", "--role=ai"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["rows"].map { |r| r["role"] }).to eq(["ai"])
  end

  it "filters by --correlation-id" do
    rc = run(["audit", "--correlation-id=abc"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["rows"].length).to eq(1)
    expect(payload["rows"].first.dig("extras", "correlation_id")).to eq("abc")
  end

  it "honors --limit" do
    rc = run(["audit", "--limit=1"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["rows"].length).to eq(1)
  end
end
