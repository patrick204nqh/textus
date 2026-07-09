RSpec.describe Textus::Adapters::WebAdapter do
  subject(:adapter) { described_class.new(api: api_double) }
  let(:api_double) { instance_double(Textus::API) }
  let(:session) { instance_double(Textus::API::Session, id: "s-1", role: "agent") }

  it "delegates action to API with params and session" do
    expect(api_double).to receive(:get).with(key: "test", session:)
    adapter.call(:get, params: { key: "test" }, session:)
  end

  it "delegates put to API with data" do
    expect(api_double).to receive(:put).with(key: "x", data: "body", meta: {}, session:)
    adapter.call(:put, params: { key: "x", data: "body", meta: {} }, session:)
  end

  it "returns API response" do
    allow(api_double).to receive(:get).and_return({ "body" => "result" })
    result = adapter.call(:get, params: { key: "test" }, session:)
    expect(result).to eq({ "body" => "result" })
  end
end
