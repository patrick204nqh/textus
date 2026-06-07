require "spec_helper"

# Proves the cookbook's HTTP-JSON recipe shape against the REAL hook surface:
# the handler is registered through the same Loader::Dsl users get from
# `Textus.hook { |reg| ... }`, and it delegates the PARSE to the built-in :json
# handler via `caps.rpc.invoke` (the registry lives on the container, not on the
# DSL — `reg.invoke` would not exist).
RSpec.describe "cookbook: http_json intake recipe" do
  let(:rpc) { Textus::Hooks::RpcRegistry.new }
  let(:events) { Textus::Hooks::EventBus.new }
  let(:reg) { Textus::Hooks::Loader::Dsl.new(events: events, rpc: rpc) }
  # The container handed to every :resolve_handler handler; only .rpc is exercised.
  let(:caps) { Struct.new(:rpc).new(rpc) }

  before do
    Textus::Hooks::Builtin.register_all(events: events, rpc: rpc)
    # The recipe hook, registered exactly as a user's `.textus/hooks/*.rb` would,
    # through the DSL's reg.on — then delegating to the built-in via caps.rpc.
    reg.on(:resolve_handler, :http_json) do |caps:, config:, args:|
      _ = config # the recipe reads config["url"]; the stub ignores it
      body = %({"name":"ada","role":"author"}) # stands in for Net::HTTP.get
      caps.rpc.invoke(:resolve_handler, :json, caps: caps,
                                               config: { "bytes" => body }, args: args)
    end
  end

  it "delegates to the built-in :json parser and yields YAML body" do
    result = rpc.invoke(
      :resolve_handler, :http_json, caps: caps,
                                    config: { "url" => "https://example.test/u" }, args: nil
    )
    expect(result[:_meta]).to eq({})
    expect(YAML.safe_load(result[:body])).to eq("name" => "ada", "role" => "author")
  end
end
