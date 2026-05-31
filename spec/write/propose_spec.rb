require "spec_helper"

RSpec.describe Textus::Write::Propose do
  let(:store) { Textus::Store.discover(File.expand_path("../../examples/project", __dir__)) }

  it "prefixes the key with the role's propose_zone and writes there" do
    env = store.as("agent").propose("decisions.adopt-x", meta: { "name" => "adopt-x" }, body: "yes\n")
    expect(env.key).to eq("proposals.decisions.adopt-x")
    expect(env.uid).not_to be_nil
  end

  it "errors when the role cannot propose" do
    expect do
      store.as("automation").propose("decisions.x", meta: { "name" => "x" }, body: "n\n")
    end.to raise_error(Textus::Error, /propose/)
  end

  it "declares an MCP contract returning {uid, etag, key}" do
    expect(described_class.contract.verb).to eq(:propose)
    expect(described_class.contract.mcp?).to be(true)
    shaped = described_class.contract.response.call(
      Struct.new(:uid, :etag, :key).new("u", "e", "proposals.x"),
    )
    expect(shaped).to eq("uid" => "u", "etag" => "e", "key" => "proposals.x")
  end
end
