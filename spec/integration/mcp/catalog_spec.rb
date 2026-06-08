require "spec_helper"

RSpec.describe Textus::MCP::Catalog do
  # Use a tmpdir copy of examples/project so put/get round-trips do not
  # mutate the committed example store (established pattern in spec/mcp/).
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) do
    src = File.expand_path("../../../examples/project/.textus", __dir__)
    FileUtils.cp_r(src, root)
    Textus::Store.new(root)
  end
  let(:session) { store.session(role: "human") }

  after { FileUtils.remove_entry(tmp) }

  describe ".tool_schemas" do
    it "advertises one entry per MCP-surfaced contract, with derived inputSchema" do
      names = described_class.tool_schemas.map { |t| t[:name] }
      expect(names).to include("get", "put", "list", "pulse", "boot")
      get = described_class.tool_schemas.find { |t| t[:name] == "get" }
      expect(get[:description]).to match(/Read one entry/)
      expect(get[:inputSchema][:required]).to eq(["key"])
      expect(get[:inputSchema][:properties]["key"]["type"]).to eq("string")
      expect(get[:inputSchema][:properties]["key"]["description"]).to be_a(String).and(satisfy { |s| !s.empty? })
    end

    # ADR 0057: the `meta:` kwarg exposes `_meta` on the wire so write matches
    # what `get` returns and what the CLI `--stdin` envelope already speaks.
    it "exposes put's meta kwarg as the `_meta` wire property" do
      put = described_class.tool_schemas.find { |t| t[:name] == "put" }
      expect(put[:inputSchema][:properties]).to have_key("_meta")
      expect(put[:inputSchema][:properties]).not_to have_key("meta")
      # ADR 0069: `_meta` is `required: false` on the contract — its real
      # requiredness lives in schema validation downstream, not on the wire — so
      # it is advertised as a property but not in the input schema's `required`.
      expect(put[:inputSchema][:required]).not_to include("_meta")
    end
  end

  describe ".call" do
    it "maps positional + keyword args and applies the response shaper (put)" do
      result = described_class.call(
        "put", session: session, store: store,
               args: { "key" => "knowledge.project", "_meta" => { "name" => "project" }, "body" => "x\n" }
      )
      expect(result.keys).to contain_exactly("uid", "etag")
    end

    it "round-trips a read via get" do
      described_class.call("put", session: session, store: store,
                                  args: { "key" => "knowledge.project", "_meta" => { "name" => "project" }, "body" => "hi\n" })
      env = described_class.call("get", session: session, store: store, args: { "key" => "knowledge.project" })
      expect(env["body"]).to eq("hi\n")
    end

    # ADR 0069: `_meta` is no longer a pre-dispatch required arg — its real
    # requiredness lives in schema validation downstream. A missing `_meta` is
    # accepted at the binder and flows to the write pipeline; an invalid `_meta`
    # is what surfaces an error (from schema validation), not its absence.
    it "accepts a missing `_meta` (its requiredness lives in schema validation)" do
      result = described_class.call("put", session: session, store: store,
                                           args: { "key" => "knowledge.project", "body" => "x\n" })
      expect(result.keys).to contain_exactly("uid", "etag")
    end

    it "surfaces a schema-validation ToolError for an invalid `_meta`" do
      expect do
        described_class.call(
          "put", session: session, store: store,
                 args: { "key" => "knowledge.project", "_meta" => { "name" => 123, "description" => "d" }, "body" => "x\n" }
        )
      end.to raise_error(Textus::MCP::ToolError, /name/)
    end

    it "raises ToolError for an unknown tool" do
      expect do
        described_class.call("nope", session: session, store: store, args: {})
      end.to raise_error(Textus::MCP::ToolError, /unknown tool/)
    end

    it "raises ToolError for a missing required arg" do
      expect do
        described_class.call("get", session: session, store: store, args: {})
      end.to raise_error(Textus::MCP::ToolError, /missing.*key/)
    end

    it "raises ToolError for a dispatcher verb that is not MCP-surfaced (e.g. audit)" do
      expect do
        described_class.call("audit", session: session, store: store, args: { "key" => "knowledge.project" })
      end.to raise_error(Textus::MCP::ToolError, /unknown tool/)
    end

    it "re-raises ContractDrift unmodified (not wrapped in ToolError)" do
      allow(store).to receive(:as).and_raise(Textus::MCP::ContractDrift.new("boom"))
      expect do
        described_class.call("get", session: session, store: store, args: { "key" => "knowledge.project" })
      end.to raise_error(Textus::MCP::ContractDrift, /boom/)
    end
  end

  describe "literal-default injection" do
    it "injects an arg's literal default when the wire omits it (ADR 0062 amendment)" do
      spec = Textus::Dispatcher::VERBS[:reconcile].contract
      _pos, kw = Textus::Contract::Binder.bind(spec, {})
      expect(kw[:dry_run]).to be(false)
    end
  end

  describe "pulse session_default cursor injection" do
    # Advance the audit log with a put, then build a session oriented at the
    # new cursor so session.cursor > 0.
    let(:advanced_session) do
      store.as("human").put("knowledge.project",
                            meta: { "name" => "project", "zone" => "knowledge" }, body: "seed\n")
      store.session(role: "human")
    end

    it "pulse without since injects session.cursor (delta from cursor, not from 0)" do
      cursor = advanced_session.cursor
      expect(cursor).to be > 0

      result = described_class.call("pulse", session: advanced_session, store: store, args: {})
      # The returned cursor reflects the current log head; since we injected the
      # session cursor, no changes happened after boot so changed should be empty.
      expect(result["changed"]).to eq([])
      expect(result["cursor"]).to eq(cursor)
    end

    it "pulse with explicit since: 0 overrides the session default and returns full history" do
      cursor = advanced_session.cursor
      expect(cursor).to be > 0

      result = described_class.call("pulse", session: advanced_session, store: store,
                                             args: { "since" => 0 })
      # since=0 means diff from the very beginning — changed will be non-empty
      expect(result["changed"]).not_to be_empty
      expect(result["cursor"]).to eq(cursor)
    end
  end
end
