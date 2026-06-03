require "spec_helper"
require "digest"

# spec/mcp/tools_spec.rb — asserts the Tools delegator routes through Catalog
# (ADR 0039). Tools.call is a thin pass-through; actual dispatch, arg-mapping,
# and response shaping are all in MCP::Catalog. Tests here verify the end-to-end
# behavior of that delegation path with a writable store fixture.
RSpec.describe Textus::MCP::Tools do
  include_context "textus_store_fixture"

  let(:manifest_yaml) do
    <<~YAML
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: knowledge,  kind: canon }
        - { name: proposals,   kind: queue }
      entries:
        - { key: identity.self,   path: identity/self.md, zone: identity, owner: human:self, kind: leaf }
        - { key: knowledge.note,    path: knowledge/note.md,  zone: knowledge,  owner: human:self, kind: leaf }
        - { key: proposals.proposal, path: proposals/proposal,  zone: proposals,   owner: agent, kind: nested }
    YAML
  end
  let(:store) { Textus::Store.new(root) }
  let(:etag) { Digest::SHA256.hexdigest(File.read(File.join(root, "manifest.yaml"))) }
  let(:session) do
    Textus::MCP::Session.new(role: "agent", cursor: 0, propose_zone: "proposals", manifest_etag: etag)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/proposals"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  # ── Delegation path ─────────────────────────────────────────────────────────

  describe "delegation to Catalog" do
    it "Tools.call produces the same result as Catalog.call for a known verb" do
      via_tools   = described_class.call("boot", session: session, store: store, args: {})
      via_catalog = Textus::MCP::Catalog.call("boot", session: session, store: store, args: {})
      expect(via_tools).to eq(via_catalog)
    end
  end

  # ── Core read/write verbs ────────────────────────────────────────────────────

  describe ".call('boot', ...)" do
    it "returns the Boot.run envelope" do
      result = described_class.call("boot", session: session, store: store, args: {})
      expect(result).to include("zones", "entries", "agent_quickstart")
      expect(result["protocol"]).to eq(Textus::PROTOCOL)
    end
  end

  describe ".call('list', ...)" do
    it "lists keys filtered by zone" do
      result = described_class.call("list", session: session, store: store, args: { "zone" => "knowledge" })
      expect(result).to be_an(Array)
    end
  end

  describe ".call('get', ...)" do
    it "raises ToolError for an unknown key" do
      expect do
        described_class.call("get", session: session, store: store, args: { "key" => "no.such.key" })
      end.to raise_error(Textus::MCP::ToolError)
    end
  end

  describe ".call('pulse', ...)" do
    it "returns pulse delta with cursor, changed, stale, pending_review, doctor" do
      result = described_class.call("pulse", session: session, store: store, args: { "since" => 0 })
      expect(result.keys).to include("cursor", "changed", "stale", "pending_review", "doctor")
    end
  end

  describe ".call('put', ...)" do
    it "writes an entry under a writable zone, returning uid + etag" do
      human_session = Textus::MCP::Session.new(
        role: "human", cursor: 0, propose_zone: "proposals", manifest_etag: etag,
      )
      result = described_class.call(
        "put",
        session: human_session, store: store,
        args: { "key" => "knowledge.note", "_meta" => { "name" => "note" }, "body" => "hi\n" }
      )
      expect(result).to include("uid", "etag")
    end
  end

  # ── First-class verbs promoted in Phase C (ADR 0039) ────────────────────────

  describe ".call('propose', ...)" do
    it "writes to the queue zone and returns the full wire envelope (incl. uid, etag, key)" do
      result = described_class.call(
        "propose",
        session: session, store: store,
        args: { "key" => "proposal.x", "_meta" => { "name" => "x" }, "body" => "draft\n" }
      )
      # ADR 0069: propose self-shapes to the full wire envelope on every surface
      # (superset of the old {uid, etag, key}).
      expect(result.keys).to include("uid", "etag", "key")
      expect(result["key"]).to eq("proposals.proposal.x")
    end
  end

  describe ".call('schema_show', ...)" do
    it "raises ToolError when the required key arg is missing" do
      expect do
        described_class.call("schema_show", session: session, store: store, args: {})
      end.to raise_error(Textus::MCP::ToolError, /missing.*key/)
    end

    it "raises ToolError for an unknown key" do
      expect do
        described_class.call("schema_show", session: session, store: store, args: { "key" => "no.such.key" })
      end.to raise_error(Textus::MCP::ToolError)
    end
  end

  describe ".call('rule_explain', ...)" do
    it "is lean by default: a Hash with at most fetch/guard keys" do
      result = described_class.call("rule_explain", session: session, store: store, args: { "key" => "knowledge.note" })
      expect(result).to be_a(Hash)
      expect(result.keys - %w[fetch guard]).to be_empty
    end

    it "with detail: true returns the verbose explanation" do
      result = described_class.call("rule_explain", session: session, store: store,
                                                    args: { "key" => "knowledge.note", "detail" => true })
      expect(result).to include(:key, :matched_blocks, :effective, :guards)
    end
  end

  describe ".call('zone_mv', ...) — applies by default (#161 F6, reverses ADR 0060)" do
    it "applies the zone move when dry_run is omitted" do
      result = described_class.call("zone_mv", session: session, store: store,
                                               args: { "from" => "knowledge", "to" => "renamed" })
      expect(result).to include("steps", "warnings")
      # F6: omitting dry_run now mutates — the manifest reflects the renamed zone.
      manifest = YAML.safe_load_file(File.join(root, "manifest.yaml"))
      zone_names = manifest.fetch("zones").map { |z| z["name"] }
      expect(zone_names).to include("renamed")
      expect(zone_names).not_to include("knowledge")
    end

    it "returns a Plan without mutating when dry_run: true is passed" do
      result = described_class.call("zone_mv", session: session, store: store,
                                               args: { "from" => "knowledge", "to" => "renamed", "dry_run" => true })
      expect(result).to include("steps", "warnings")
      zone_names = YAML.safe_load_file(File.join(root, "manifest.yaml"))
                       .fetch("zones").map { |z| z["name"] }
      expect(zone_names).to include("knowledge")
      expect(zone_names).not_to include("renamed")
    end
  end

  describe ".call('where', ...) — graph-read now on MCP (ADR 0060)" do
    it "resolves a key's zone and path" do
      result = described_class.call("where", session: session, store: store, args: { "key" => "knowledge.note" })
      expect(result["zone"]).to eq("knowledge")
    end
  end

  # ── Maintenance verbs ────────────────────────────────────────────────────────

  describe ".call('key_mv_prefix', ..., dry_run: true)" do
    it "returns a plan without mutating files" do
      result = described_class.call(
        "key_mv_prefix", session: session, store: store,
                         args: { "from_prefix" => "knowledge", "to_prefix" => "renamed", "dry_run" => true }
      )
      expect(result).to include("steps", "warnings")
    end
  end

  # ── Error handling ───────────────────────────────────────────────────────────

  describe ".call with an unknown tool name" do
    it "raises ToolError" do
      expect do
        described_class.call("nope", session: session, store: store, args: {})
      end.to raise_error(Textus::MCP::ToolError, /unknown tool/)
    end
  end
end
