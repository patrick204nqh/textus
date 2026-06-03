require "spec_helper"
require "stringio"
require "time"

Textus::CLI.verbs # triggers Runner.install! so Verb::GenFreshness exists

RSpec.describe Textus::CLI::Verb::GenFreshness do
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

      rules:
        - match: knowledge.doc
          fetch: { ttl: 1h, on_stale: warn }
    YAML
    File.write(File.join(root, "zones/knowledge/doc.md"), <<~MD)
      ---
      name: doc
      last_fetched_at: "#{Time.now.utc.iso8601}"
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
    expect(payload["rows"].first["key"]).to eq("knowledge.doc")
    expect(payload["rows"].first["status"]).to eq("fresh")
  end

  it "honors --zone filter" do
    rc = run(["freshness", "--zone=nonexistent"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["rows"]).to eq([])
  end

  it "honors --prefix filter" do
    rc = run(["freshness", "--prefix=knowledge.doc"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["rows"].map { |r| r["key"] }).to eq(["knowledge.doc"])
  end
end
