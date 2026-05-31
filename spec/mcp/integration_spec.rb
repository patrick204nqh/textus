require "spec_helper"
require "stringio"

# spec/mcp/integration_spec.rb — full JSON-RPC round-trip tests.
# Sends real JSON-RPC messages through the Server I/O loop and asserts on the
# parsed responses. Verb names are the current ADR 0036/0039 names only; no
# retired aliases (tick / find / read / write / fetch_stale) appear here.
RSpec.describe "MCP end-to-end" do
  include_context "textus_store_fixture"

  before do
    %w[zones/identity zones/working zones/review schemas hooks].each do |d|
      FileUtils.mkdir_p(File.join(root, d))
    end
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: working,  kind: canon }
        - { name: review,   kind: queue }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  def run_session(requests_arr)
    store = Textus::Store.new(root)
    payload = requests_arr.map { |r| JSON.dump(r.merge(jsonrpc: "2.0")) }.join("\n") + "\n"
    out = StringIO.new
    Textus::MCP::Server.new(store: store, stdin: StringIO.new(payload), stdout: out).run
    out.string.lines.map { |l| JSON.parse(l) }
  end

  it "handshake → tools/list → tools/call boot/pulse all succeed" do
    responses = run_session([
                              { id: 1, method: "initialize",
                                params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
                              { id: 2, method: "tools/list", params: {} },
                              { id: 3, method: "tools/call", params: { name: "boot",  arguments: {} } },
                              { id: 4, method: "tools/call", params: { name: "pulse", arguments: { since: 0 } } },
                            ])
    expect(responses.map { |r| r["id"] }).to eq([1, 2, 3, 4])
    expect(responses.all? { |r| r["error"].nil? }).to be(true)
  end

  it "tools/list advertises derived catalog names including the Phase-C verbs" do
    responses = run_session([
                              { id: 1, method: "initialize",
                                params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
                              { id: 2, method: "tools/list", params: {} },
                            ])
    list_response = responses.find { |r| r["id"] == 2 }
    tool_names = list_response.dig("result", "tools").map { |t| t["name"] }
    expect(tool_names).to include("boot", "pulse", "list", "get", "put",
                                  "propose", "schema", "rules")
    expect(tool_names).not_to include("tick", "find", "read", "write", "fetch_stale")
    # Self-updating: must equal the catalog's authoritative name list
    expect(tool_names.sort).to eq(Textus::MCP::Catalog.names.sort)
  end

  it "put → get round-trip succeeds via JSON-RPC tools/call" do
    responses = run_session([
                              { id: 1, method: "initialize",
                                params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
                              { id: 2, method: "tools/call",
                                params: { name: "put",
                                          arguments: { key: "working.note",
                                                       meta: { "name" => "note" }, body: "round-trip\n" } } },
                              { id: 3, method: "tools/call",
                                params: { name: "get", arguments: { key: "working.note" } } },
                            ])
    expect(responses.map { |r| r["id"] }).to eq([1, 2, 3])
    expect(responses.all? { |r| r["error"].nil? }).to be(true)
    get_result = responses.find { |r| r["id"] == 3 }.dig("result", "content", 0, "text")
    parsed = JSON.parse(get_result)
    expect(parsed["body"]).to eq("round-trip\n")
  end
end
