require "spec_helper"
require "digest"

RSpec.describe Textus::MCP::Tools do
  include_context "textus_store_fixture"

  let(:manifest_yaml) do
    <<~YAML
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: working,  kind: canon }
        - { name: review,   kind: queue }
      entries:
        - { key: identity.self,   path: identity/self.md, zone: identity, schema: null, owner: human:self, kind: leaf }
        - { key: working.note,    path: working/note.md,  zone: working,  schema: null, owner: human:self, kind: leaf }
        - { key: review.proposal, path: review/proposal,  zone: review,   schema: null, owner: agent, nested: true, kind: nested }
    YAML
  end
  let(:store) { Textus::Store.new(root) }
  let(:etag) { Digest::SHA256.hexdigest(File.read(File.join(root, "manifest.yaml"))) }
  let(:session) do
    Textus::MCP::Session.new(role: "agent", cursor: 0, propose_zone: "review", manifest_etag: etag)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  describe ".call('boot', ...)" do
    it "returns the Boot.run envelope" do
      result = described_class.call("boot", session: session, store: store, args: {})
      expect(result).to include("zones", "entries", "agent_quickstart")
      expect(result["protocol"]).to eq(Textus::PROTOCOL)
    end
  end

  describe ".call('list', ...)" do
    it "lists keys filtered by zone" do
      result = described_class.call("list", session: session, store: store, args: { "zone" => "working" })
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

  describe ".call('nope', ...)" do
    it "raises ToolError for an unknown tool" do
      expect do
        described_class.call("nope", session: session, store: store, args: {})
      end.to raise_error(Textus::MCP::ToolError, /unknown tool/)
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
        role: "human", cursor: 0, propose_zone: "review", manifest_etag: etag,
      )
      result = described_class.call(
        "put",
        session: human_session, store: store,
        args: { "key" => "working.note", "meta" => { "name" => "note" }, "body" => "hi\n" }
      )
      expect(result).to include("uid", "etag")
    end
  end

  describe ".call('propose', ...)" do
    # propose is a composed tool promoted to a first-class verb in Phase C (ADR 0039);
    # until then it is not in the derived catalog and raises ToolError.
    it "raises ToolError (not yet a catalog verb; promoted in Phase C)" do
      expect do
        described_class.call(
          "propose",
          session: session, store: store,
          args: { "key" => "proposal.x", "meta" => { "name" => "x" }, "body" => "draft\n" }
        )
      end.to raise_error(Textus::MCP::ToolError)
    end
  end

  describe ".call('schema', ...)" do
    it "raises ToolError for an unknown family" do
      expect do
        described_class.call("schema", session: session, store: store, args: { "family" => "nope" })
      end.to raise_error(Textus::MCP::ToolError)
    end
  end

  describe ".call('rules', ...)" do
    # rules is a composed tool promoted to a first-class verb in Phase C (ADR 0039);
    # until then it is not in the derived catalog and raises ToolError.
    it "raises ToolError (not yet a catalog verb; promoted in Phase C)" do
      expect do
        described_class.call("rules", session: session, store: store, args: { "key" => "working.note" })
      end.to raise_error(Textus::MCP::ToolError)
    end
  end

  describe ".call('key_mv_prefix', ..., dry_run: true)" do
    it "returns a plan without mutating files" do
      result = described_class.call(
        "key_mv_prefix", session: session, store: store,
                         args: { "from_prefix" => "working", "to_prefix" => "renamed", "dry_run" => true }
      )
      expect(result).to include("steps", "warnings")
    end
  end
end
