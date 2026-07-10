RSpec.describe Textus::Adapters::McpAdapter do
  subject(:adapter) { described_class.new(api:) }
  let(:api) { instance_double(Textus::API) }
  let(:session) { instance_double(Textus::API::Session, id: "s-1", role: "agent") }

  before do
    allow(api).to receive(:open_session).with(role: "agent").and_return(session)
  end

  it "opens session and dispatches action with string-keyed params" do
    expect(api).to receive(:get).with(key: "test", session:)
    adapter.call(:get, params: { "key" => "test" })
  end

  it "reuses session_id across calls" do
    expect(api).to receive(:resume_session).with(id: "s-1").twice.and_return(session)
    expect(api).to receive(:get).with(key: "a", session:)
    expect(api).to receive(:get).with(key: "b", session:)

    adapter.call(:get, params: { "key" => "a" }, session_id: "s-1")
    adapter.call(:get, params: { "key" => "b" })
  end

  it "deep stringifies nested params" do
    expect(api).to receive(:put).with(data: { "nested" => "value" }, key: "x", session:)
    adapter.call(:put, params: { key: "x", data: { nested: "value" } })
  end

  it "returns API response directly" do
    allow(api).to receive(:get).with(key: "test", session:).and_return({ "body" => "result" })
    result = adapter.call(:get, params: { "key" => "test" })
    expect(result).to eq({ "body" => "result" })
  end
end
