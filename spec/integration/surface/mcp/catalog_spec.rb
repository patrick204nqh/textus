require "spec_helper"

RSpec.describe Textus::Surface::MCP::Catalog do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge notebook proposals artifacts], schemas: {
                          "project" => File.read(File.expand_path("../../../../.textus/schemas/project.yaml", __dir__)),
                        }, manifest: <<~YAML)
                          version: textus/4
                          roles:
                            - { name: human,      can: [author, propose] }
                            - { name: agent,      can: [propose, keep] }
                            - { name: automation, can: [converge] }
                          lanes:
                            - { name: knowledge, kind: canon }
                            - { name: notebook,  kind: workspace }
                            - { name: proposals, kind: queue }
                            - { name: artifacts, kind: machine }
                          entries:
                            - { key: knowledge.project, path: knowledge/project.md, lane: knowledge, schema: project, kind: leaf }
                            - { key: notebook.notes, path: notebook/notes, lane: notebook, kind: nested, nested: true }
                            - { key: proposals.notes, path: proposals/notes, lane: proposals, kind: nested, nested: true }
                        YAML
  end
  let(:session) { store.session(role: "human") }

  describe ".build_tools" do
    it "returns an MCP::Tool for each MCP-surfaced verb" do
      tools = described_class.build_tools(instance_double(Textus::Surface::MCP::Server, dispatch: nil))
      names = tools.map(&:tool_name)
      expect(names).to include("get", "put", "list", "pulse", "boot")
    end

    it "each tool has a description and input_schema" do
      tools = described_class.build_tools(instance_double(Textus::Surface::MCP::Server, dispatch: nil))
      get_tool = tools.find { |t| t.tool_name == "get" }
      expect(get_tool.description).to be_a(String).and(satisfy { |s| !s.empty? })
      schema = get_tool.input_schema.to_h
      expect(schema).to have_key(:required)
    end

    # ADR 0057: put's _meta wire property
    it "exposes put's _meta in the input_schema properties" do
      tools = described_class.build_tools(instance_double(Textus::Surface::MCP::Server, dispatch: nil))
      put_tool = tools.find { |t| t.tool_name == "put" }
      schema = put_tool.input_schema.to_h
      props = schema[:properties]
      has_meta = props.key?(:_meta) || props.key?("_meta")
      no_meta  = !props.key?(:meta) && !props.key?("meta")
      expect(has_meta).to be(true), "expected _meta in #{props.keys.inspect}"
      expect(no_meta).to be(true)
      required = schema[:required] || []
      expect(required).not_to include("_meta")
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
      end.to raise_error(Textus::Surface::MCP::ToolError, /name/)
    end

    it "raises ToolError for an unknown tool" do
      expect do
        described_class.call("nope", session: session, store: store, args: {})
      end.to raise_error(Textus::Surface::MCP::ToolError, /unknown tool/)
    end

    it "raises ToolError for a missing required arg" do
      expect do
        described_class.call("get", session: session, store: store, args: {})
      end.to raise_error(Textus::Surface::MCP::ToolError, /missing.*key/)
    end

    it "raises ToolError for a dispatcher verb that is not MCP-surfaced (e.g. audit)" do
      expect do
        described_class.call("audit", session: session, store: store, args: { "key" => "knowledge.project" })
      end.to raise_error(Textus::Surface::MCP::ToolError, /unknown tool/)
    end

    it "wraps gateway errors in ToolError" do
      expect do
        described_class.call("get", session: session, store: store, args: { "key" => "no.such.key" })
      end.to raise_error(Textus::Surface::MCP::ToolError)
    end
  end

  describe "literal-default injection" do
    it "injects an arg's literal default when the wire omits it (ADR 0062 amendment)" do
      spec = Textus::Action::VERBS[:jobs].contract
      kw = Textus::Gate::Binder.bind(spec, {})
      expect(kw[:state]).to eq("ready")
    end
  end

  describe "pulse session_default cursor injection" do
    # Advance the audit log with a put, then build a session oriented at the
    # new cursor so session.cursor > 0.
    let(:advanced_session) do
      store.as("human").put("knowledge.project",
                            meta: { "name" => "project", "lane" => "knowledge" }, body: "seed\n")
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
