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
    it "writes to the queue zone and returns uid, etag, key" do
      result = described_class.call(
        "propose",
        session: session, store: store,
        args: { "key" => "proposal.x", "_meta" => { "name" => "x" }, "body" => "draft\n" }
      )
      expect(result.keys).to contain_exactly("uid", "etag", "key")
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

  describe ".call('rules', ...)" do
    it "returns a Hash with at most fetch/guard keys" do
      result = described_class.call("rules", session: session, store: store, args: { "key" => "knowledge.note" })
      expect(result).to be_a(Hash)
      expect(result.keys - %w[fetch guard]).to be_empty
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
