require "spec_helper"

RSpec.describe "Textus per-event sugar" do
  let(:reg) { Textus::Hooks::Registry.new }

  around { |ex| Textus.with_registry(reg) { ex.run } }

  describe ".fetch" do
    it "registers a fetch hook by name" do
      Textus.fetch(:local_file) do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "ok" }
      end
      out = reg.rpc_callable(:fetch, :local_file).call(store: nil, config: {}, args: {})
      expect(out[:body]).to eq("ok")
    end

    it "accepts a string name and normalizes to a symbol" do
      Textus.fetch("from_string") do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "s" }
      end
      expect(reg.rpc_names(:fetch)).to include(:from_string)
    end

    it "raises outside with_registry" do
      Thread.new do
        expect do
          Textus.fetch(:naked) { |config:, args:, **| [config, args] }
        end.to raise_error(Textus::UsageError, /no active registry/)
      end.join
    end
  end

  describe ".reduce" do
    it "registers a reduce hook" do
      Textus.reduce(:top2) { |rows:, **| rows.first(2) } # rubocop:disable Lint/UnexpectedBlockArity
      expect(reg.rpc_callable(:reduce, :top2).call(store: nil, rows: [1, 2, 3], config: nil)).to eq([1, 2])
    end
  end

  describe ".check" do
    it "registers a doctor check" do
      Textus.check(:always_ok) do |store:|
        [store]
        []
      end
      expect(reg.rpc_callable(:check, :always_ok).call(store: nil)).to eq([])
    end
  end

  describe ".put with keys: filter" do
    it "registers a pub-sub put hook with key filter" do
      captured = []
      Textus.put(:tap, keys: ["working.*"]) { |key:, **| captured << key }
      reg.listeners(:put, key: "working.x").first[:callable].call(store: nil, key: "working.x", envelope: {})
      expect(captured).to eq(["working.x"])
    end
  end

  describe ".delete / .refresh / .build / .accept" do
    it "registers each pub-sub event" do
      Textus.delete(:d)  { |key:, **| key }
      Textus.refresh(:r) { |key:, envelope:, change:, **| [key, envelope, change] }
      Textus.build(:b)   { |key:, envelope:, sources:, **| [key, envelope, sources] }
      Textus.accept(:a)  { |key:, target_key:, **| [key, target_key] }

      expect(reg.pubsub_handlers(:delete).map { _1[:name] }).to include(:d)
      expect(reg.pubsub_handlers(:refresh).map { _1[:name] }).to include(:r)
      expect(reg.pubsub_handlers(:build).map { _1[:name] }).to include(:b)
      expect(reg.pubsub_handlers(:accept).map { _1[:name] }).to include(:a)
    end
  end
end
