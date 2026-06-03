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
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

      rules:
        - match: "knowledge.*"
          fetch: { ttl: 1h, on_stale: warn }
        - match: knowledge.doc
          fetch: { ttl: 5m, on_stale: sync }
          intake_handler_allowlist: [src_a]
    YAML
  end

  describe "textus rule list" do
    it "emits every parsed block" do
      rc = run(%w[rule list])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("rule_list")
      expect(payload["policies"].length).to eq(2)
      expect(payload["policies"].map { |b| b["match"] }).to eq(["knowledge.*", "knowledge.doc"])
      expect(payload["policies"].first["fetch"]["ttl_seconds"]).to eq(3600)
    end

    it "serializes retention as a plain hash with integer seconds" do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

        rules:
          - match: knowledge.doc
            retention: { expire_after: 30d }
      YAML
      rc = run(%w[rule list])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      block = payload["policies"].find { |b| b["match"] == "knowledge.doc" }
      expect(block["retention"]).to eq("expire_after" => 2_592_000, "archive_after" => nil)
    end
  end

  describe "textus rule explain KEY" do
    it "is lean by default: the effective {fetch, guard} winners only" do
      rc = run(%w[rule explain knowledge.doc])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("rule_explain")
      expect(payload.keys - %w[protocol verb fetch guard]).to be_empty
      expect(payload["fetch"]["ttl_seconds"]).to eq(300)
    end

    it "with --detail returns matched blocks and effective values for a key" do
      rc = run(%w[rule explain knowledge.doc --detail])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("rule_explain")
      expect(payload["key"]).to eq("knowledge.doc")
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

  describe "textus rule lint --against=FILE (generated, ADR 0068)" do
    it "reads the candidate YAML from --against and diffs its rules" do
      cand = File.join(tmp, "cand.yaml")
      File.write(cand, <<~YAML)
        rules:
          - match: knowledge.doc
            fetch: { ttl: 5m, on_stale: sync }
            intake_handler_allowlist: [src_a]
          - match: knowledge.new
            fetch: { ttl: 2h, on_stale: warn }
      YAML
      rc = run(["rule", "lint", "--against=#{cand}"])
      expect(rc).to eq(0), "stderr: #{stderr.string}"
      payload = JSON.parse(stdout.string)
      ops = payload["steps"].map { |s| [s["op"], s["match"]] }
      expect(ops).to include(["add_rule", "knowledge.new"], ["remove_rule", "knowledge.*"])
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
