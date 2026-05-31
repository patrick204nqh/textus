require "spec_helper"
require "stringio"

RSpec.describe "textus rule group" do
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
        - { name: working, kind: canon }
      entries:
        - { key: working.doc, path: working/doc.md, zone: working, kind: leaf}

      rules:
        - match: "working.*"
          fetch: { ttl: 1h, on_stale: warn }
        - match: working.doc
          fetch: { ttl: 5m, on_stale: sync }
          intake_handler_allowlist: [src_a]
    YAML
  end

  describe "textus rule list" do
    it "emits every parsed block" do
      rc = run(%w[rule list])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("policy_list")
      expect(payload["policies"].length).to eq(2)
      expect(payload["policies"].map { |b| b["match"] }).to eq(["working.*", "working.doc"])
      expect(payload["policies"].first["fetch"]["ttl_seconds"]).to eq(3600)
    end
  end

  describe "textus rule explain KEY" do
    it "returns matched blocks and effective values for a key" do
      rc = run(%w[rule explain working.doc])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("policy_explain")
      expect(payload["key"]).to eq("working.doc")
      expect(payload["matched_blocks"].length).to eq(2)
      expect(payload["effective"]["fetch"]["ttl_seconds"]).to eq(300)
      expect(payload["effective"]["handler_allowlist"]).to eq(["src_a"])
    end

    it "raises UsageError when no key is supplied" do
      rc = run(%w[rule explain])
      expect(rc).not_to eq(0)
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
    end
  end

  describe "textus rule (no subcommand)" do
    it "lists valid subcommands" do
      run(["rule"])
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
      expect(stderr.string).to match(/rule requires a subcommand:.*explain.*list/i)
    end
  end
end
