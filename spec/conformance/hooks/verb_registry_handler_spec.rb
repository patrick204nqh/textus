require "spec_helper"

# Proves the dogfood verb_registry_handler hook (ADR 0097): the handler is
# loaded through the real Loader so it exercises the same code path as the
# live `.textus/hooks/` directory, and invoked through the RpcRegistry — the
# same surface every intake handler goes through at runtime.
RSpec.describe "verb_registry_handler" do
  let(:events) { Textus::Hooks::EventBus.new }
  let(:rpc)    { Textus::Hooks::RpcRegistry.new }
  # Minimal caps stub: only .rpc is required by resolve_handler handlers.
  let(:caps)   { Struct.new(:rpc).new(rpc) }

  before do
    # Load just the one hook file in isolation by copying it into a tmpdir so
    # other .textus/hooks/*.rb files do not register into this fresh registry.
    handler_path = File.expand_path("../../../.textus/hooks/verb_registry_handler.rb", __dir__)
    Dir.mktmpdir do |dir|
      FileUtils.cp(handler_path, File.join(dir, "verb_registry_handler.rb"))
      Textus::Hooks::Loader.new(events: events, rpc: rpc).load_dir(dir)
    end
  end

  it "registers a :verbs resolve_handler" do
    expect(rpc.names(:resolve_handler)).to include(:verbs)
  end

  it "emits one content row per top-level verb, sorted by name, with name + summary" do
    result = rpc.invoke(:resolve_handler, :verbs, caps: caps, config: {}, args: [])
    verbs = result["content"]["verbs"]

    expect(verbs).to be_an(Array)
    names = verbs.map { |v| v["name"] }
    expect(names).to eq(names.sort)
    expect(names).to include("get", "put", "boot")
    expect(verbs.first.keys).to include("name", "summary")
  end

  it "includes all top-level CLI verbs" do
    result = rpc.invoke(:resolve_handler, :verbs, caps: caps, config: {}, args: [])
    names = result["content"]["verbs"].map { |v| v["name"] }
    expect(names).to include(*Textus::CLI.verbs.keys)
  end

  it "has deterministic output (sorted by name)" do
    r1 = rpc.invoke(:resolve_handler, :verbs, caps: caps, config: {}, args: [])
    r2 = rpc.invoke(:resolve_handler, :verbs, caps: caps, config: {}, args: [])
    expect(r1["content"]["verbs"].map { |v| v["name"] })
      .to eq(r2["content"]["verbs"].map { |v| v["name"] })
  end
end
