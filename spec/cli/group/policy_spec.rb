require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"

RSpec.describe "textus policy group" do
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
      policies:
        - match: "working.*"
          refresh: { ttl: 1h, on_stale: warn }
        - match: working.doc
          refresh: { ttl: 5m, on_stale: sync }
          handler_allowlist: [src_a]
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  describe "textus policy list" do
    it "emits every parsed block" do
      rc = run(%w[policy list])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("policy_list")
      expect(payload["policies"].length).to eq(2)
      expect(payload["policies"].map { |b| b["match"] }).to eq(["working.*", "working.doc"])
      expect(payload["policies"].first["refresh"]["ttl_seconds"]).to eq(3600)
    end
  end

  describe "textus policy explain KEY" do
    it "returns matched blocks and effective values for a key" do
      rc = run(%w[policy explain working.doc])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("policy_explain")
      expect(payload["key"]).to eq("working.doc")
      expect(payload["matched_blocks"].length).to eq(2)
      expect(payload["effective"]["refresh"]["ttl_seconds"]).to eq(300)
      expect(payload["effective"]["handler_allowlist"]).to eq(["src_a"])
    end

    it "raises UsageError when no key is supplied" do
      rc = run(%w[policy explain])
      expect(rc).not_to eq(0)
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
    end
  end

  describe "textus policy (no subcommand)" do
    it "lists valid subcommands" do
      run(["policy"])
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
      expect(stderr.string).to match(/policy requires a subcommand:.*list.*explain/i)
    end
  end
end
