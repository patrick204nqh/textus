require "spec_helper"
require "digest"

# spec/integration/mcp/catalog_dispatch_spec.rb — end-to-end dispatch coverage
# for MCP::Catalog.call (ADR 0039). Covers verb behaviors with a writable store
# fixture that catalog_spec's read-only example project does not exercise.
# (Was tools_spec.rb; MCP::Tools — a pure pass-through to Catalog — was deleted
# in ADR 0101, so this suite now describes Catalog directly.)
RSpec.describe Textus::Surface::MCP::Catalog do
  include_context "textus_store_fixture"

  let(:manifest_yaml) do
    <<~YAML
      version: textus/4
      lanes:
        - { name: identity, kind: canon }
        - { name: knowledge,  kind: canon }
        - { name: proposals,   kind: queue }
      entries:
        - { key: identity.self,   path: identity/self.md, lane: identity, owner: human:self, kind: leaf }
        - { key: knowledge.note,    path: knowledge/note.md,  lane: knowledge,  owner: human:self, kind: leaf }
        - { key: proposals.proposal, path: proposals/proposal,  lane: proposals,   owner: agent, kind: nested }
    YAML
  end
  let(:store) { Textus::Store.new(root) }
  let(:agent_store) { store.with_role("agent") }
  let(:human_store) { store.with_role("human") }

  before do
    FileUtils.mkdir_p(File.join(root, "data/identity"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/proposals"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    File.write(File.join(root, "data/identity/self.md"), "---\nuid: 1234567890abcdef\n---\nidentity self\n")
    File.write(File.join(root, "data/knowledge/note.md"), "---\nuid: abcdef1234567890\n---\nknowledge note\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  # ── Core read/write verbs ────────────────────────────────────────────────────

  describe ".call('boot', ...)" do
    it "returns the Boot.run envelope" do
      result = described_class.call("boot", store: agent_store, args: {})
      expect(result).to include("lanes", "agent_quickstart")
      expect(result).not_to have_key("index_key")
      expect(result["protocol"]).to eq(Textus::PROTOCOL)
    end
  end

  describe ".call('list', ...)" do
    it "lists keys filtered by zone" do
      result = described_class.call("list", store: agent_store, args: { "lane" => "knowledge" })
      expect(result).to be_an(Array)
    end
  end

  describe ".call('get', ...)" do
    it "raises ToolError for an unknown key" do
      expect do
        described_class.call("get", store: agent_store, args: { "key" => "no.such.key" })
      end.to raise_error(Textus::Surface::MCP::ToolError)
    end
  end

  describe ".call('pulse', ...)" do
    it "returns pulse delta with cursor, changed, pending_review, contract_etag, index_etag" do
      result = described_class.call("pulse", store: agent_store, args: { "since" => 0 })
      expect(result.keys).to include("cursor", "changed", "pending_review", "contract_etag", "index_etag")
    end
  end

  describe ".call('put', ...)" do
    it "writes an entry under a writable zone, returning uid + etag" do
      result = described_class.call(
        "put",
        store: human_store,
        args: { "key" => "knowledge.note", "_meta" => { "name" => "note" }, "body" => "hi\n" },
      )
      expect(result).to include("uid", "etag")
    end
  end

  # ── First-class verbs promoted in Phase C (ADR 0039) ────────────────────────

  describe ".call('propose', ...)" do
    it "writes to the queue zone and returns the full wire envelope (incl. uid, etag, key)" do
      result = described_class.call(
        "propose",
        store: agent_store,
        args: { "key" => "proposal.x", "_meta" => { "name" => "x" }, "body" => "draft\n" },
      )
      expect(result.keys).to include("uid", "etag", "key")
      expect(result["key"]).to eq("proposals.proposal.x")
    end
  end

  # ── accept/reject over MCP — gated by author_held, not by transport (ADR 0072) ──

  describe ".call('accept' / 'reject', ...) — capability-gated on MCP (ADR 0072 F7)" do
    def queue_proposal(leaf)
      described_class.call(
        "propose",
        store: agent_store,
        args: {
          "key" => "proposal.#{leaf}",
          "_meta" => {
            "name" => leaf,
            "proposal" => { "target_key" => "knowledge.note", "action" => "put" },
            "_meta" => { "name" => "note" },
          },
          "body" => "draft\n",
        },
      )
      "proposals.proposal.#{leaf}"
    end

    it "accept is exposed in the derived catalog" do
      expect(Textus::Surface::MCP::Catalog.names).to include("accept", "reject")
    end

    it "refuses accept for a default agent connection (lacks author)" do
      pending_key = queue_proposal("a1")
      expect do
        described_class.call("accept", store: agent_store,
                                       args: { "pending_key" => pending_key })
      end.to raise_error(Textus::Surface::MCP::ToolError, /author/)
    end

    it "allows accept for a human-role connection" do
      pending_key = queue_proposal("a2")
      result = described_class.call("accept", store: human_store,
                                              args: { "pending_key" => pending_key })
      expect(result["accepted"]).to eq(pending_key)
      expect(result["target_key"]).to eq("knowledge.note")
    end

    it "refuses reject for a default agent connection (lacks author)" do
      pending_key = queue_proposal("r1")
      expect do
        described_class.call("reject", store: agent_store,
                                       args: { "pending_key" => pending_key })
      end.to raise_error(Textus::Surface::MCP::ToolError, /author/)
    end

    it "allows reject for a human-role connection" do
      pending_key = queue_proposal("r2")
      result = described_class.call("reject", store: human_store,
                                              args: { "pending_key" => pending_key })
      expect(result["rejected"]).to eq(pending_key)
    end
  end

  describe ".call('schema_show', ...)" do
    it "raises ToolError when the required key arg is missing" do
      expect do
        described_class.call("schema_show", store: agent_store, args: {})
      end.to raise_error(Textus::Surface::MCP::ToolError, /missing.*key/)
    end

    it "raises ToolError for an unknown key" do
      expect do
        described_class.call("schema_show", store: agent_store, args: { "key" => "no.such.key" })
      end.to raise_error(Textus::Surface::MCP::ToolError)
    end
  end

  describe ".call('rule_explain', ...)" do
    it "is lean by default: a Hash with at most fetch/guard keys" do
      result = described_class.call("rule_explain", store: agent_store, args: { "key" => "knowledge.note" })
      expect(result).to be_a(Hash)
      expect(result.keys - %w[fetch guard]).to be_empty
    end

    it "with detail: true returns the verbose explanation" do
      result = described_class.call("rule_explain", store: agent_store,
                                                    args: { "key" => "knowledge.note", "detail" => true })
      expect(result).to include(:key, :matched_blocks, :effective, :guards)
    end
  end

  describe ".call('data_mv', ...) — applies by default (#161 F6, reverses ADR 0060)" do
    it "applies the data lane move when dry_run is omitted" do
      result = described_class.call("data_mv", store: agent_store,
                                               args: { "from" => "knowledge", "to" => "renamed" })
      expect(result).to include("steps", "warnings")
      manifest = YAML.safe_load_file(File.join(root, "manifest.yaml"))
      lane_names = manifest.fetch("lanes").map { |z| z["name"] }
      expect(lane_names).to include("renamed")
      expect(lane_names).not_to include("knowledge")
    end

    it "returns a Plan without mutating when dry_run: true is passed" do
      result = described_class.call("data_mv", store: agent_store,
                                               args: { "from" => "knowledge", "to" => "renamed", "dry_run" => true })
      expect(result).to include("steps", "warnings")
      lane_names = YAML.safe_load_file(File.join(root, "manifest.yaml"))
                       .fetch("lanes").map { |z| z["name"] }
      expect(lane_names).to include("knowledge")
      expect(lane_names).not_to include("renamed")
    end
  end

  describe ".call('where', ...) — graph-read now on MCP (ADR 0060)" do
    it "resolves a key's zone and path" do
      result = described_class.call("where", store: agent_store, args: { "key" => "knowledge.note" })
      expect(result["lane"]).to eq("knowledge")
    end
  end

  describe ".call('key_mv_prefix', ..., dry_run: true)" do
    it "returns a plan without mutating files" do
      result = described_class.call(
        "key_mv_prefix", store: agent_store,
                         args: { "from_prefix" => "knowledge", "to_prefix" => "renamed", "dry_run" => true }
      )
      expect(result).to include("steps", "warnings")
    end
  end

  describe ".call with an unknown tool name" do
    it "raises ToolError" do
      expect do
        described_class.call("nope", store: agent_store, args: {})
      end.to raise_error(Textus::Surface::MCP::ToolError, /unknown tool/)
    end
  end

  # ── Newly-exposed observability verbs (verb-registry standardization) ──────

  describe ".call('uid', ...)" do
    it "returns the entry's stable uid" do
      result = described_class.call("uid", store: human_store, args: { "key" => "identity.self" })
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  describe ".call('blame', ...)" do
    it "returns an array of audit rows annotated with git info" do
      result = described_class.call("blame", store: human_store, args: { "key" => "identity.self" })
      expect(result).to be_an(Array)
    end
  end

  describe ".call('audit', ...)" do
    it "returns an array of audit rows" do
      result = described_class.call("audit", store: human_store, args: {})
      expect(result).to be_an(Array)
    end
  end

  describe ".call('audit', ...) with an expired cursor" do
    it "raises Textus::CursorExpired, not a generic ToolError, so the MCP server can emit JSONRPC -32002" do
      allow(human_store.audit_log).to receive(:min_available_seq).and_return(20)

      expect do
        described_class.call("audit", store: human_store, args: { "seq_since" => 3 })
      end.to raise_error(Textus::CursorExpired)
    end
  end

  describe ".call('rule_list', ...)" do
    it "returns an array of rule blocks" do
      result = described_class.call("rule_list", store: human_store, args: {})
      expect(result).to be_an(Array)
    end
  end

  describe ".call('published', ...)" do
    it "returns an array of published entries" do
      result = described_class.call("published", store: human_store, args: {})
      expect(result).to be_an(Array)
    end
  end

  describe ".call('doctor', ...)" do
    it "returns a health-check result hash" do
      result = described_class.call("doctor", store: human_store, args: {})
      expect(result).to include("ok")
    end
  end

  it "advertises all six previously CLI-only verbs as MCP tool names" do
    expect(Textus::Surface::MCP::Catalog.names).to include(
      "uid", "blame", "audit", "rule_list", "published", "doctor"
    )
  end
end
