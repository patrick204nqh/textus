require "spec_helper"

RSpec.describe Textus::MCP::Catalog do
  # Use a tmpdir copy of examples/project so put/get round-trips do not
  # mutate the committed example store (established pattern in spec/mcp/).
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) do
    src = File.expand_path("../../examples/project/.textus", __dir__)
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
      expect(get[:inputSchema][:properties]["key"]).to eq("type" => "string")
    end
  end

  describe ".call" do
    it "maps positional + keyword args and applies the response shaper (put)" do
      result = described_class.call(
        "put", session: session, store: store,
               args: { "key" => "knowledge.project", "meta" => { "name" => "project" }, "body" => "x\n" }
      )
      expect(result.keys).to contain_exactly("uid", "etag")
    end

    it "round-trips a read via get" do
      described_class.call("put", session: session, store: store,
                                  args: { "key" => "knowledge.project", "meta" => { "name" => "project" }, "body" => "hi\n" })
      env = described_class.call("get", session: session, store: store, args: { "key" => "knowledge.project" })
      expect(env["body"]).to eq("hi\n")
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
  end
end
