require "spec_helper"

RSpec.describe "MCP serve role wiring (ADR 0040)" do
  let(:store) { Textus::Protocol::Session.open(File.expand_path("../../../../.textus", __dir__)) }

  def role_handed_to_server(argv)
    captured = nil
    fake = instance_double(Textus::Surface::MCP::Server, run: nil)
    allow(Textus::Surface::MCP::Server).to receive(:new) do |**kw|
      captured = kw[:role]
      fake
    end

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TEXTUS_ROLE").and_return(nil)

    adapter = Textus::Adapters::CliAdapter.new
    adapter.call(
      ["mcp", "serve", *argv],
      gate: store.gate,
      store_resolver: -> { store },
      stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new,
      cwd: Dir.pwd,
    )
    captured
  end

  it "defaults to the agent role with no override" do
    expect(role_handed_to_server([])).to eq("agent")
  end

  it "honors an explicit --as override" do
    expect(role_handed_to_server(["--as=human"])).to eq("human")
  end
end
