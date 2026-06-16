require "spec_helper"
require "stringio"

# spec/mcp/integration_spec.rb — full JSON-RPC round-trip tests.
# Sends real JSON-RPC messages through the Server I/O loop and asserts on the
# parsed responses. Verb names are the current ADR 0036/0039 names only; no
# retired aliases (tick / find / read / write / fetch_stale) appear here.
RSpec.describe "MCP end-to-end" do
  include_context "textus_store_fixture"

  before do
    %w[data/identity zones/knowledge zones/proposals schemas hooks].each do |d|
      FileUtils.mkdir_p(File.join(root, d))
    end
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: identity, kind: canon }
        - { name: knowledge,  kind: canon }
        - { name: proposals,   kind: queue }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  def run_session(requests_arr)
    store = Textus::Store.new(root)
    payload = requests_arr.map { |r| JSON.dump(r.merge(jsonrpc: "2.0")) }.join("\n") + "\n"
    out = StringIO.new
    Textus::Surfaces::MCP::Server.new(store: store, stdin: StringIO.new(payload), stdout: out).run
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
                                  "propose", "schema_show", "rule_explain",
                                  "deps", "rdeps", "where")
    expect(tool_names).not_to include("tick", "find", "read", "write", "fetch_stale", "rules")
    # Self-updating: must equal the catalog's authoritative name list
    expect(tool_names.sort).to eq(Textus::Surfaces::MCP::Catalog.names.sort)
  end

  it "pulse cursor advances: no-since pulse after put returns only the new entry; second no-since pulse returns empty changed" do
    # Shape of the proof:
    #   1. initialize  → session cursor = audit_log.latest_seq at that instant (call it C0)
    #   2. put         → writes an audit row; audit_log.latest_seq becomes C1 > C0
    #   3. pulse (no since) → session_default :cursor injects C0; changed must contain the
    #                          put row (seq > C0); server then advances session cursor to C1
    #   4. pulse (no since) → session_default :cursor now injects C1; changed must be []
    #
    # If the server were accidentally using since=0 for both calls, step 4 would still
    # return the put entry in changed (re-emitting from the beginning). The empty changed
    # in step 4 is only correct when the session cursor was genuinely advanced after step 3.
    responses = run_session([
                              { id: 1, method: "initialize",
                                params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
                              { id: 2, method: "tools/call",
                                params: { name: "put",
                                          arguments: { key: "knowledge.note",
                                                       "_meta" => { "name" => "note" }, body: "cursor-advance-probe\n" } } },
                              { id: 3, method: "tools/call",
                                params: { name: "pulse", arguments: {} } },
                              { id: 4, method: "tools/call",
                                params: { name: "pulse", arguments: {} } },
                            ])
    expect(responses.map { |r| r["id"] }).to eq([1, 2, 3, 4])
    expect(responses.all? { |r| r["error"].nil? }).to be(true)

    pulse1 = JSON.parse(responses.find { |r| r["id"] == 3 }.dig("result", "content", 0, "text"))
    pulse2 = JSON.parse(responses.find { |r| r["id"] == 4 }.dig("result", "content", 0, "text"))

    # First pulse (using session cursor C0): must see the put entry
    expect(pulse1["changed"].length).to eq(1)
    expect(pulse1["changed"].first["key"]).to eq("knowledge.note")
    cursor_after_first_pulse = pulse1["cursor"]
    expect(cursor_after_first_pulse).to be > 0

    # Second pulse (using advanced session cursor C1): must see nothing new
    expect(pulse2["changed"]).to be_empty
    # Cursor is stable — no new writes since the first pulse advanced it
    expect(pulse2["cursor"]).to eq(cursor_after_first_pulse)
  end

  it "deletes one key through the MCP catalog (ADR 0060 amendment)" do
    responses = run_session([
                              { id: 1, method: "initialize",
                                params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
                              { id: 2, method: "tools/call",
                                params: { name: "put",
                                          arguments: { key: "knowledge.note",
                                                       "_meta" => { "name" => "note" }, body: "to-be-deleted\n" } } },
                              { id: 3, method: "tools/call",
                                params: { name: "key_delete", arguments: { "key" => "knowledge.note" } } },
                            ])
    expect(responses.map { |r| r["id"] }).to eq([1, 2, 3])
    expect(responses.all? { |r| r["error"].nil? }).to be(true)
    delete_result = JSON.parse(responses.find { |r| r["id"] == 3 }.dig("result", "content", 0, "text"))
    expect(delete_result).to include("deleted" => true, "key" => "knowledge.note")
  end

  it "renames one key through the MCP catalog (single-key mv, ADR 0060 amendment)" do
    # Extend the manifest with a second entry so mv has a valid manifest target
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: identity, kind: canon }
        - { name: knowledge,  kind: canon }
        - { name: proposals,   kind: queue }
      entries:
        - { key: knowledge.note,    path: knowledge/note.md,    lane: knowledge, owner: human:self, kind: leaf }
        - { key: knowledge.renamed, path: knowledge/renamed.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML

    responses = run_session([
                              { id: 1, method: "initialize",
                                params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
                              { id: 2, method: "tools/call",
                                params: { name: "put",
                                          arguments: { key: "knowledge.note",
                                                       "_meta" => { "name" => "note" }, body: "to-be-renamed\n" } } },
                              { id: 3, method: "tools/call",
                                params: { name: "key_mv",
                                          arguments: { "old_key" => "knowledge.note", "new_key" => "knowledge.renamed" } } },
                            ])
    expect(responses.map { |r| r["id"] }).to eq([1, 2, 3])
    expect(responses.all? { |r| r["error"].nil? }).to be(true)
    mv_result = JSON.parse(responses.find { |r| r["id"] == 3 }.dig("result", "content", 0, "text"))
    expect(mv_result).to include("ok" => true, "from_key" => "knowledge.note", "to_key" => "knowledge.renamed")
  end

  it "put → get round-trip succeeds via JSON-RPC tools/call" do
    responses = run_session([
                              { id: 1, method: "initialize",
                                params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
                              { id: 2, method: "tools/call",
                                params: { name: "put",
                                          arguments: { key: "knowledge.note",
                                                       "_meta" => { "name" => "note" }, body: "round-trip\n" } } },
                              { id: 3, method: "tools/call",
                                params: { name: "get", arguments: { key: "knowledge.note" } } },
                            ])
    expect(responses.map { |r| r["id"] }).to eq([1, 2, 3])
    expect(responses.all? { |r| r["error"].nil? }).to be(true)
    get_result = responses.find { |r| r["id"] == 3 }.dig("result", "content", 0, "text")
    parsed = JSON.parse(get_result)
    expect(parsed["body"]).to eq("round-trip\n")
  end
end
