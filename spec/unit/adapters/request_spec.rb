RSpec.describe Textus::Adapters::Request do
  it "creates with verb only" do
    r = described_class.new(action: :get)
    expect(r.action).to eq(:get)
    expect(r.params).to eq({})
    expect(r.role).to be_nil
    expect(r.session_id).to be_nil
    expect(r.correlation_id).to be_nil
  end

  it "accepts all fields" do
    r = described_class.new(action: :put, params: { key: "test" }, role: "human", session_id: "s1", correlation_id: "cid1")
    expect(r.action).to eq(:put)
    expect(r.params).to eq({ key: "test" })
    expect(r.role).to eq("human")
    expect(r.session_id).to eq("s1")
    expect(r.correlation_id).to eq("cid1")
  end

  it "is frozen" do
    r = described_class.new(action: :get)
    expect(r).to be_frozen
  end

  it "defaults params to empty hash" do
    r = described_class.new(action: :list)
    expect(r.params).to eq({})
  end
end
