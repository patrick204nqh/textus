require "spec_helper"

RSpec.describe "Textus.on DSL — core behaviour" do
  let(:reg) { Textus::Hooks::Registry.new }

  around { |ex| Textus.with_registry(reg) { ex.run } }

  it "registers an intake hook via :intake event" do
    Textus.on(:intake, :gh) do |store:, config:, args:|
      [store, config, args]
      { _meta: {}, body: "x" }
    end
    out = reg.rpc_callable(:intake, :gh).call(store: nil, config: {}, args: {})
    expect(out[:body]).to eq("x")
  end

  it "registers a reducer via :reduce event" do
    Textus.on(:reduce, :top) do |store:, rows:, config:|
      [store, config]
      rows.first(2)
    end
    expect(reg.rpc_callable(:reduce, :top).call(store: nil, rows: [1, 2, 3], config: nil)).to eq([1, 2])
  end

  it "registers a doctor check via :check event" do
    Textus.on(:check, :always_ok) do |store:|
      [store]
      []
    end
    expect(reg.rpc_callable(:check, :always_ok).call(store: nil)).to eq([])
  end

  it "registers a pub-sub hook via :put event with keys: filter" do
    captured = []
    Textus.on(:put, :tap, keys: ["working.*"]) do |store:, key:, envelope:|
      [store, envelope]
      captured << key
    end
    reg.listeners(:put, key: "working.x").first[:callable].call(store: nil, key: "working.x", envelope: {})
    expect(captured).to eq(["working.x"])
  end

  it "raises when called outside with_registry" do
    Thread.new do
      expect do
        Textus.on(:put, :naked) { |store:, key:, envelope:| [store, key, envelope] }
      end.to raise_error(Textus::UsageError, /no active registry/)
    end.join
  end

  it "raises when called without a block" do
    expect do
      Textus.on(:put, :no_block)
    end.to raise_error(Textus::UsageError, /hook needs a block/)
  end

  it "no longer exposes Textus.action / Textus.reducer / Textus.doctor_check" do
    expect(Textus).not_to respond_to(:action)
    expect(Textus).not_to respond_to(:reducer)
    expect(Textus).not_to respond_to(:doctor_check)
  end
end
