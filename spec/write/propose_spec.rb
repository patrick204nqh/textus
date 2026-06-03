require "spec_helper"

RSpec.describe Textus::Write::Propose do
  # Use a tmpdir copy of examples/project so propose writes do not mutate the
  # committed example store (same pattern as spec/mcp/catalog_spec.rb).
  let(:tmp) { Dir.mktmpdir }
  let(:store) do
    src = File.expand_path("../../examples/project/.textus", __dir__)
    FileUtils.cp_r(src, File.join(tmp, ".textus"))
    Textus::Store.new(File.join(tmp, ".textus"))
  end

  after { FileUtils.remove_entry(tmp) }

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

  it "declares an MCP contract whose single view emits the full wire envelope (ADR 0069)" do
    expect(described_class.contract.verb).to eq(:propose)
    expect(described_class.contract.mcp?).to be(true)
    wire = { "uid" => "u", "etag" => "e", "key" => "proposals.x", "zone" => "proposals" }
    env = instance_double(Textus::Envelope, to_h_for_wire: wire)
    shaped = described_class.contract.view(:default).call(env, {})
    expect(shaped).to eq(wire)
  end
end
