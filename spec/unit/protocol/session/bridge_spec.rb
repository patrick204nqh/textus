RSpec.describe Textus::Protocol::Session::Bridge do
  subject(:bridge) { described_class.new(container:, gate:) }

  let(:container) do
    instance_double(
      Textus::Protocol::Container,
      store: store_double,
      manifest: manifest_double,
      schemas: schemas_double,
      layout: layout_double,
      workflows: workflows_double,
      root: "/tmp/.textus",
      ttl_evaluator: ttl_double,
    )
  end
  let(:gate) { instance_double(Textus::Protocol::Gate) }
  let(:store_double)   { double("store") }
  let(:manifest_double) { double("manifest") }
  let(:schemas_double)  { double("schemas") }
  let(:layout_double)   { double("layout") }
  let(:workflows_double) { double("workflows") }
  let(:ttl_double)      { double("ttl_evaluator") }

  it "is a Data.define with container and gate" do
    expect(bridge.container).to eq(container)
    expect(bridge.gate).to eq(gate)
  end

  it "delegates store to container" do
    expect(bridge.store).to eq(store_double)
  end

  it "delegates manifest to container" do
    expect(bridge.manifest).to eq(manifest_double)
  end

  it "delegates schemas to container" do
    expect(bridge.schemas).to eq(schemas_double)
  end

  it "delegates layout to container" do
    expect(bridge.layout).to eq(layout_double)
  end

  it "delegates workflows to container" do
    expect(bridge.workflows).to eq(workflows_double)
  end

  it "delegates root to container" do
    expect(bridge.root).to eq("/tmp/.textus")
  end

  it "delegates ttl_evaluator to container" do
    expect(bridge.ttl_evaluator).to eq(ttl_double)
  end

  it "delegates dispatch to gate" do
    call_obj = double("call")
    expect(gate).to receive(:dispatch).with(:agent, :get, { key: "foo" }, call: call_obj)
    bridge.dispatch(:agent, :get, { key: "foo" }, call: call_obj)
  end

  it "supports with() for immutable updates" do
    new_gate = double("new_gate")
    updated = bridge.with(gate: new_gate)
    expect(bridge.gate).to eq(gate)
    expect(updated.gate).to eq(new_gate)
    expect(updated.container).to eq(container)
  end
end
