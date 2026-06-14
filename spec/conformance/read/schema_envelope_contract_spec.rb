require "spec_helper"

RSpec.describe "Read::SchemaEnvelope MCP contract (ADR 0039)" do
  let(:store) { Textus::Store.new(File.expand_path("../../../.textus", __dir__)) }

  it "is exposed on MCP under the name 'schema_show', keyed by entry key" do
    c = Textus::Action::SchemaEnvelope.contract
    expect(c.verb).to eq(:schema_show)
    expect(c.mcp?).to be(true)
    expect(c.args.map(&:name)).to eq([:key])
  end

  it "the MCP catalog dispatches schema by key" do
    session = store.session(role: "human")
    out = Textus::Surfaces::MCP::Catalog.call("schema_show", session: session, store: store,
                                                             args: { "key" => "knowledge.project" })
    expect(out["key"]).to eq("knowledge.project")
    expect(out).to have_key("schema")
  end
end
