RSpec.describe "MCP agent workflow — end-to-end" do
  include_context "textus/4 conformance fixture"

  let(:agent_store) { Textus::Protocol::Session.open(root, role: "agent") }
  let(:agent_server) { server_for(agent_store, role: "agent") }
  let(:human_server) { server_for(human_store, role: "human") }
  let(:human_store) { Textus::Protocol::Session.open(root, role: "human") }

  def server_for(store, role:)
    Textus::Surface::MCP::Server.new(store:, role:, stdin: StringIO.new, stdout: StringIO.new)
  end

  def dispatch(server, verb, args)
    resp = server.dispatch(verb, args, nil)
    raise "empty content for #{verb}" if resp.content.empty?

    JSON.parse(resp.content.first[:text] || resp.content.first["text"])
  rescue StandardError => e
    raise "dispatch(#{verb}) failed: #{e.class}: #{e.message}"
  end

  it "session_open works end-to-end" do
    result = dispatch(agent_server, :session_open, {})
    expect(result).to have_key("session_id")
    expect(result["status"]).to eq("active")
  end

  it "runs a full session_open → get → put → propose → accept → get cycle" do
    # 1. session_open
    open_result = dispatch(agent_server, :session_open, {})
    session_id = open_result["session_id"]

    # 2. get the session entry
    get_session = dispatch(agent_server, :get, { key: "scratchpad.sessions.#{session_id}.session" })
    expect(get_session["key"]).to eq("scratchpad.sessions.#{session_id}.session")

    # 3. put a knowledge entry (human)
    put_result = dispatch(human_server, :put, {
                            key: "knowledge.intent.0002-test-intent",
                            _meta: { name: "0002-test-intent" },
                            body: "# Test intent\n\nBody content.\n",
                          })
    expect(put_result["ok"]).to be true
    expect(put_result["uid"]).to be_a(String)
    intent_uid = put_result["uid"]

    # 4. verify the entry
    get_intent = dispatch(agent_server, :get, { key: "knowledge.intent.0002-test-intent" })
    expect(get_intent.dig("_meta", "uid")).to eq(intent_uid)

    # 5. propose a change
    propose_result = dispatch(agent_server, :propose, {
                                key: "intent-update",
                                _meta: {
                                  proposal: { target_key: "knowledge.intent.0002-test-intent", action: "put" },
                                },
                                body: "# Test intent (updated)\n\nUpdated body.\n",
                              })
    pending_key = propose_result["key"]

    # 6. diff
    diff_result = dispatch(agent_server, :diff, { pending_key: })
    expect(diff_result["pending_key"]).to eq(pending_key)
    expect(diff_result["target_key"]).to eq("knowledge.intent.0002-test-intent")

    # 7. accept (human)
    accept_result = dispatch(human_server, :accept, { pending_key: })
    expect(accept_result["accepted"]).to eq(pending_key)

    # 8. verify accepted content
    get_updated = dispatch(agent_server, :get, { key: "knowledge.intent.0002-test-intent" })
    expect(get_updated["body"]).to include("(updated)")

    # 9. list
    list_result = dispatch(agent_server, :list, { prefix: "knowledge.intent" })
    expect(list_result.map { |e| e["key"] }).to include("knowledge.intent.0002-test-intent")

    # 10. pulse
    pulse_result = dispatch(agent_server, :pulse, {})
    expect(pulse_result["cursor"]).to be > 0
  end

  it "rejects a proposal" do
    propose_result = dispatch(agent_server, :propose, {
                                key: "to-reject",
                                _meta: {
                                  proposal: { target_key: "knowledge.contacts.reject-person", action: "put" },
                                },
                                body: "Name: Test\nRelationship: peer\nOrg: Acme\n",
                              })
    pending_key = propose_result["key"]

    reject_result = dispatch(human_server, :reject, { pending_key:, reason: "not needed" })
    expect(reject_result["rejected"]).to eq(pending_key)
    expect(reject_result["reason"]).to eq("not needed")

    get_proposal = begin
      dispatch(agent_server, :get, { key: pending_key })
    rescue StandardError
      nil
    end
    expect(get_proposal).to be_nil.or(be_a(Hash).and(have_key("error")))
  end
end
