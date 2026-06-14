require "spec_helper"

# ADR 0040: the session's propose_lane derives from the connection's resolved
# role, not a manifest-wide proposer_role fallback. White-box on @session is
# intentional — the field is server-internal session state.
RSpec.describe "MCP session propose_lane derives from the connection role (ADR 0040)" do
  let(:store) { Textus::Store.new(File.expand_path("../../../.textus", __dir__)) }

  def session_after_initialize(role)
    request = JSON.dump("jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => {}) + "\n"
    server = Textus::Surfaces::MCP::Server.new(
      store: store, stdin: StringIO.new(request), stdout: StringIO.new, role: role,
    )
    server.run
    server.instance_variable_get(:@session)
  end

  it "resolves the queue zone for an agent connection" do
    session = session_after_initialize("agent")
    expect(session.propose_lane).to eq(store.manifest.policy.propose_lane_for("agent"))
    expect(session.propose_lane).not_to be_nil
  end

  it "yields nil propose_lane for a role that cannot propose" do
    # `automation` holds `converge` — it does not grant propose, so
    # propose_lane_for("automation") => nil.
    # Under the old proposer_role fallback this would have been the queue zone;
    # the new per-connection derivation must return nil here.
    session = session_after_initialize("automation")
    expect(session.propose_lane).to be_nil
  end
end
