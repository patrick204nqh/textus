require "spec_helper"

RSpec.describe "Textus.hook DSL" do
  let(:reg) { Textus::Hooks::Registry.new }

  around { |ex| Textus.with_registry(reg) { ex.run } }

  it "registers an intake hook via :intake event" do
    Textus.hook(:intake, :gh) do |store:, config:, args:|
      [store, config, args]
      { _meta: {}, body: "x" }
    end
    out = reg.rpc_callable(:intake, :gh).call(store: nil, config: {}, args: {})
    expect(out[:body]).to eq("x")
  end

  it "registers a reducer via :reduce event" do
    Textus.hook(:reduce, :top) do |store:, rows:, config:|
      [store, config]
      rows.first(2)
    end
    expect(reg.rpc_callable(:reduce, :top).call(store: nil, rows: [1, 2, 3], config: nil)).to eq([1, 2])
  end

  it "registers a doctor check via :check event" do
    Textus.hook(:check, :always_ok) do |store:|
      [store]
      []
    end
    expect(reg.rpc_callable(:check, :always_ok).call(store: nil)).to eq([])
  end

  it "registers a pub-sub hook via :put event with keys: filter" do
    captured = []
    Textus.hook(:put, :tap, keys: ["working.*"]) do |store:, key:, envelope:|
      [store, envelope]
      captured << key
    end
    reg.listeners(:put, key: "working.x").first[:callable].call(store: nil, key: "working.x", envelope: {})
    expect(captured).to eq(["working.x"])
  end

  it "raises when called outside with_registry" do
    Thread.new do
      expect do
        Textus.hook(:put, :naked) { |store:, key:, envelope:| [store, key, envelope] }
      end.to raise_error(Textus::UsageError, /no active registry/)
    end.join
  end

  it "no longer exposes Textus.action / Textus.reducer / Textus.doctor_check" do
    expect(Textus).not_to respond_to(:action)
    expect(Textus).not_to respond_to(:reducer)
    expect(Textus).not_to respond_to(:doctor_check)
  end
end
