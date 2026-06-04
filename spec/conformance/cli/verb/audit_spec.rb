require "spec_helper"
require "stringio"

RSpec.describe "textus audit (generated via coerce:since + cli view, ADR 0068)" do
  include_context "textus_store_fixture"

  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.open(audit_log_path(root), "w") do |f|
      f.puts JSON.generate({ "ts" => "2026-05-01T00:00:00Z", "role" => "human",
                             "verb" => "put", "key" => "knowledge.doc",
                             "extras" => { "correlation_id" => "abc" } })
      f.puts JSON.generate({ "ts" => "2026-05-02T00:00:00Z", "role" => "ai",
                             "verb" => "put", "key" => "knowledge.doc" })
    end
  end

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
