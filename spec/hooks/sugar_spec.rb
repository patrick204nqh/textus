require "spec_helper"

RSpec.describe "Textus per-event sugar" do
  let(:reg) { Textus::Hooks::Registry.new }

  around { |ex| Textus.with_registry(reg) { ex.run } }

  describe ".intake" do
    it "registers an intake hook by name" do
      Textus.intake(:local_file) do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "ok" }
      end
      out = reg.rpc_callable(:intake, :local_file).call(store: nil, config: {}, args: {})
      expect(out[:body]).to eq("ok")
    end

    it "accepts a string name and normalizes to a symbol" do
      Textus.intake("from_string") do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "s" }
      end
      expect(reg.rpc_names(:intake)).to include(:from_string)
    end

    it "raises outside with_registry" do
      Thread.new do
        expect do
          Textus.intake(:naked) { |config:, args:, **| [config, args] }
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

  describe ".deleted / .refreshed / .built / .accepted / .published" do
    it "registers each pub-sub event" do
      Textus.deleted(:d)   { |key:, **| key }
      Textus.refreshed(:r) { |key:, envelope:, change:, **| [key, envelope, change] }
      Textus.built(:b)     { |key:, envelope:, sources:, **| [key, envelope, sources] }
      Textus.accepted(:a)  { |key:, target_key:, **| [key, target_key] }
      Textus.published(:p) { |key:, envelope:, source:, target:, **| [key, envelope, source, target] }

      expect(reg.pubsub_handlers(:deleted).map { _1[:name] }).to include(:d)
      expect(reg.pubsub_handlers(:refreshed).map { _1[:name] }).to include(:r)
      expect(reg.pubsub_handlers(:built).map { _1[:name] }).to include(:b)
      expect(reg.pubsub_handlers(:accepted).map { _1[:name] }).to include(:a)
      expect(reg.pubsub_handlers(:published).map { _1[:name] }).to include(:p)
    end
  end

  describe ".refresh_began / .refresh_failed / .refresh_detached" do
    it "registers each lifecycle event" do
      Textus.refresh_began(:s)    { |key:, mode:, **| [key, mode] }
      Textus.refresh_failed(:f)   { |key:, error_class:, error_message:, **| [key, error_class, error_message] }
      Textus.refresh_detached(:d) { |key:, started_at:, budget_ms:, **| [key, started_at, budget_ms] }

      expect(reg.pubsub_handlers(:refresh_began).map { _1[:name] }).to include(:s)
      expect(reg.pubsub_handlers(:refresh_failed).map { _1[:name] }).to include(:f)
      expect(reg.pubsub_handlers(:refresh_detached).map { _1[:name] }).to include(:d)
    end
  end
end
