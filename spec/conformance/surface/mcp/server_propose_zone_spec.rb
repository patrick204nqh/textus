require "spec_helper"

RSpec.describe "MCP session propose_lane derives from the connection role (ADR 0040)" do
  let(:store) { Textus::Store.new(File.expand_path("../../../../.textus", __dir__)) }

  def store_after_initialize(role)
    request = JSON.dump("jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => {}) + "\n"
    server = Textus::Surface::MCP::Server.new(
      store: store, stdin: StringIO.new(request), stdout: StringIO.new, role: role,
    )
    server.run
    server.instance_variable_get(:@store)
  end

  it "resolves the queue zone for an agent connection" do
    s = store_after_initialize("agent")
    expect(s.propose_lane).to eq(store.manifest.policy.propose_lane_for("agent"))
    expect(s.propose_lane).not_to be_nil
  end

  it "yields nil propose_lane for a role that cannot propose" do
    s = store_after_initialize("automation")
    expect(s.propose_lane).to be_nil
  end
end
