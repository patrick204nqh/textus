require "spec_helper"

# ADR 0040: the session's propose_zone derives from the connection's resolved
# role, not a manifest-wide proposer_role fallback. White-box on @session is
# intentional — the field is server-internal session state.
RSpec.describe "MCP session propose_zone derives from the connection role (ADR 0040)" do
  let(:store) { Textus::Store.discover(File.expand_path("../../examples/project", __dir__)) }

  def session_after_initialize(role)
    request = JSON.dump("jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => {}) + "\n"
    server = Textus::MCP::Server.new(
      store: store, stdin: StringIO.new(request), stdout: StringIO.new, role: role,
    )
    server.run
    server.instance_variable_get(:@session)
  end

  it "resolves the queue zone for an agent connection" do
    session = session_after_initialize("agent")
    expect(session.propose_zone).to eq(store.manifest.policy.propose_zone_for("agent"))
    expect(session.propose_zone).not_to be_nil
  end
end
