RSpec.describe Textus::Adapters::WebAdapter do
  subject(:adapter) { described_class.new(api:) }
  let(:api) { instance_double(Textus::API) }
  let(:session) { instance_double(Textus::API::Session, id: "s-1", role: "agent") }

  before do
    allow(api).to receive(:open_session).with(role: "agent").and_return(session)
  end

  it "opens session and delegates action to API with params" do
    expect(api).to receive(:get).with(key: "test", session:)
    adapter.call(:get, params: { key: "test" })
  end

  it "resumes session when session_id is given" do
    expect(api).to receive(:resume_session).with(id: "s-1").and_return(session)
    expect(api).to receive(:put).with(key: "x", data: "body", meta: {}, session:)
    adapter.call(:put, params: { key: "x", data: "body", meta: {} }, session_id: "s-1")
  end

  it "returns API response" do
    allow(api).to receive(:get).with(key: "test", session:).and_return({ "body" => "result" })
    result = adapter.call(:get, params: { key: "test" })
    expect(result).to eq({ "body" => "result" })
  end
end
