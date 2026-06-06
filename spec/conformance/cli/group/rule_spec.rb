require "spec_helper"

RSpec.describe "textus rule group" do
  include_context "textus_store_fixture"
  include_context "cli invocation"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

      rules:
        # ADR 0091: no `on:` discriminator — grammar is keyed (ttl/action → age; strategy → dependency)
        - match: "knowledge.*"
          upkeep: { ttl: 1h, action: warn }
        - match: knowledge.doc
          upkeep: { ttl: 5m, action: warn }
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
      expect(payload["policies"].first["upkeep"]["ttl_seconds"]).to eq(3600)
      expect(payload["policies"].first["upkeep"]["action"]).to eq("warn")
    end

    it "serializes a stale upkeep as a plain hash with integer seconds" do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.doc, path: knowledge/doc.md, zone: knowledge, kind: leaf}

        rules:
          - match: knowledge.doc
            upkeep: { ttl: 30d, action: drop }
      YAML
      rc = run(%w[rule list])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      block = payload["policies"].find { |b| b["match"] == "knowledge.doc" }
      expect(block["upkeep"]).to eq(
        "ttl_seconds" => 2_592_000, "action" => "drop", "budget_ms" => nil,
      )
    end
  end

  describe "textus rule explain KEY" do
    it "is lean by default: the effective {upkeep, guard} winners only" do
      rc = run(%w[rule explain knowledge.doc])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("rule_explain")
      expect(payload.keys - %w[protocol verb upkeep guard]).to be_empty
      expect(payload["upkeep"]["ttl_seconds"]).to eq(300)
      expect(payload["upkeep"]["action"]).to eq("warn")
    end

    it "with --detail returns matched blocks and effective values for a key" do
      rc = run(%w[rule explain knowledge.doc --detail])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("rule_explain")
      expect(payload["key"]).to eq("knowledge.doc")
      expect(payload["matched_blocks"].length).to eq(2)
      expect(payload["effective"]["upkeep"]["ttl_seconds"]).to eq(300)
      expect(payload["effective"]["upkeep"]["action"]).to eq("warn")
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
            upkeep: { ttl: 5m, action: warn }
            intake_handler_allowlist: [src_a]
          - match: knowledge.new
            upkeep: { ttl: 2h, action: warn }
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
