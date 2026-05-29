require "spec_helper"

RSpec.describe Textus::Hooks::RpcRegistry do
  let(:rpc) { described_class.new }

  it "registers and invokes a named RPC callable" do
    rpc.register(:resolve_intake, :http) { |args:, **| "fetched #{args[:trigger_key]}" }
    result = rpc.invoke(:resolve_intake, :http, caps: double("caps"), config: {}, args: { trigger_key: "k" }) # rubocop:disable RSpec/VerifiedDoubles
    expect(result).to eq("fetched k")
  end

  it "raises on duplicate registration" do
    rpc.register(:resolve_intake, :http) { |**| nil }
    expect { rpc.register(:resolve_intake, :http) { |**| nil } }
      .to raise_error(Textus::UsageError, /already registered/)
  end

  it "raises on unknown event" do
    expect { rpc.register(:not_real, :x) { |**| nil } }
      .to raise_error(Textus::UsageError, /unknown RPC event/)
  end

  it "rejects a pubsub event name" do
    expect { rpc.register(:entry_put, :x) { |**| nil } }
      .to raise_error(Textus::UsageError, /entry_put is a pubsub event/)
  end

  it "injects caps under the kwarg name the callable declares" do
    received = nil
    rpc.register(:transform_rows, :pluck) do |caps:, rows:, **|
      received = caps
      rows
    end
    caps = double("ReadCaps") # rubocop:disable RSpec/VerifiedDoubles
    rpc.invoke(:transform_rows, :pluck, caps: caps, rows: [], config: {})
    expect(received).to be(caps)
  end

  it "raises UsageError at registration if a callable declares legacy `store:` instead of `caps:`" do
    expect do
      rpc.register(:transform_rows, :legacy) do |store:, rows:, _config:|
        _ = store
        rows
      end
    end.to raise_error(Textus::UsageError, /must accept kwargs.*missing: caps/)
  end
end
