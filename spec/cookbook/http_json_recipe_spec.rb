require "spec_helper"

# Proves the cookbook's HTTP-JSON recipe shape: a user hook that does the I/O
# (stubbed here) and delegates the PARSE to the built-in :json handler.
RSpec.describe "cookbook: http_json intake recipe" do
  let(:rpc) { Textus::Hooks::RpcRegistry.new }

  before do
    Textus::Hooks::Builtin.register_all(events: Textus::Hooks::EventBus.new, rpc: rpc)
    # The recipe hook: stub the network, delegate to built-in :json.
    rpc.register(:resolve_intake, :http_json) do |config:, **|
      _ = config # the recipe reads config["url"]; the stub ignores it
      body = %({"name":"ada","role":"author"}) # stands in for Net::HTTP.get
      rpc.invoke(:resolve_intake, :json, caps: nil, config: { "bytes" => body }, args: nil)
    end
  end

  it "delegates to the built-in :json parser and yields YAML body" do
    result = rpc.invoke(
      :resolve_intake, :http_json, caps: nil,
                                   config: { "url" => "https://example.test/u" }, args: nil
    )
    expect(result[:_meta]).to eq({})
    expect(YAML.safe_load(result[:body])).to eq("name" => "ada", "role" => "author")
  end
end
