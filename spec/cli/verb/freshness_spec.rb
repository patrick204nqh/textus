require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"
require "time"

RSpec.describe Textus::CLI::Verb::Freshness do
  include_context "textus_store_fixture"

  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, writable_by: [human, script] }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working }
      policies:
        - match: working.doc
          refresh: { ttl: 1h, on_stale: warn }
    YAML
    File.write(File.join(root, "zones/working/doc.md"), <<~MD)
      ---
      name: doc
      last_refreshed_at: "#{Time.now.utc.iso8601}"
      ---
      body
    MD
  end

  it "emits a JSON envelope with verb=freshness and rows" do
    rc = run(["freshness"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["verb"]).to eq("freshness")
    expect(payload["rows"]).to be_an(Array)
    expect(payload["rows"].first["key"]).to eq("working.doc")
    expect(payload["rows"].first["status"]).to eq("fresh")
  end

  it "honors --zone filter" do
    rc = run(["freshness", "--zone=nonexistent"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["rows"]).to eq([])
  end

  it "honors --prefix filter" do
    rc = run(["freshness", "--prefix=working.doc"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["rows"].map { |r| r["key"] }).to eq(["working.doc"])
  end
end
