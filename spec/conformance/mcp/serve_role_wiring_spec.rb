require "spec_helper"

# Reconciliation guard (ADR 0040 §2/§4): the MCP transport pins the `agent`
# role by default — the agent channel proposes, it does not inherit human
# authority. A --as override still works. If the wiring regresses (server built
# without the resolved role, or the default flips back to human), this fails.
RSpec.describe "MCP serve role wiring (ADR 0040)" do
  let(:store) { Textus::Store.discover(File.expand_path("../../../examples/project", __dir__)) }

  def role_handed_to_server(argv)
    verb = Textus::CLI::Verb::MCPServe.new(
      stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new,
    )
    verb.parse(argv)

    captured = nil
    fake = instance_double(Textus::MCP::Server, run: nil)
    allow(Textus::MCP::Server).to receive(:new) do |**kw|
      captured = kw[:role]
      fake
    end

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TEXTUS_ROLE").and_return(nil)

    verb.call(store)
    captured
  end

  it "defaults to the agent role with no override" do
    expect(role_handed_to_server([])).to eq("agent")
  end

  it "honors an explicit --as override" do
    expect(role_handed_to_server(["--as", "human"])).to eq("human")
  end
end
