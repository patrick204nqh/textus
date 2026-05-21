require "spec_helper"

RSpec.describe "Textus.define block DSL" do
  let(:reg) { Textus::Hooks::Registry.new }

  around { |ex| Textus.with_registry(reg) { ex.run } }

  it "registers a single fetch under the block's name" do
    Textus.define :local_file do
      fetch { |**| { _meta: {}, body: "x" } }
    end
    expect(reg.rpc_names(:fetch)).to include(:local_file)
  end

  it "registers both fetch and reduce under the same name" do
    Textus.define :combo do
      fetch  { |**| { _meta: {}, body: "f" } }
      reduce { |rows:, **| rows.reverse }
    end

    expect(reg.rpc_names(:fetch)).to include(:combo)
    expect(reg.rpc_names(:reduce)).to include(:combo)
  end

  it "registers a pub-sub event with keys: filter" do
    captured = []
    Textus.define :listener do
      put(keys: ["working.*"]) { |key:, **| captured << key }
    end

    reg.listeners(:put, key: "working.x").first[:callable].call(store: nil, key: "working.x", envelope: {})
    expect(captured).to eq(["working.x"])
  end

  it "raises outside with_registry" do
    Thread.new do
      expect do
        Textus.define(:naked) { fetch { |config:, args:, **| [config, args] } }
      end.to raise_error(Textus::UsageError, /no active registry/)
    end.join
  end

  it "raises when the block calls an unknown event" do
    expect do
      Textus.define(:bad) { nonsense }
    end.to raise_error(NameError)
  end
end
