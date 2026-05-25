require "spec_helper"

RSpec.describe "Textus.on DSL" do
  let(:registry) { Textus::Hooks::Registry.new }

  it "registers RPC handlers via Textus.on" do
    Textus.with_registry(registry) do
      Textus.on(:resolve_intake, :my_handler) { |**| { _meta: {}, body: "ok" } }
    end
    expect(registry.rpc_names(:resolve_intake)).to include(:my_handler)
  end

  it "registers pub-sub listeners via Textus.on with keys:" do
    Textus.with_registry(registry) do
      Textus.on(:entry_put, :my_listener, keys: ["working.*"]) { |**| nil }
    end
    expect(registry.pubsub_handlers(:entry_put).map { |h| h[:name] }).to include(:my_listener)
  end

  it "no longer responds to Textus.intake (sugar removed)" do
    expect(Textus).not_to respond_to(:intake)
  end

  it "no longer responds to Textus.reduce (sugar removed)" do
    expect(Textus).not_to respond_to(:reduce)
  end

  it "no longer responds to Textus.check (sugar removed)" do
    expect(Textus).not_to respond_to(:check)
  end

  it "no longer responds to Textus.put (sugar removed)" do
    expect(Textus).not_to respond_to(:put)
  end

  it "no longer responds to Textus.hook (escape hatch removed)" do
    expect(Textus).not_to respond_to(:hook)
  end
end
