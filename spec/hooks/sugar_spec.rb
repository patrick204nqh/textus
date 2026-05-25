require "spec_helper"

RSpec.describe "Textus.on — full event coverage" do
  let(:reg) { Textus::Hooks::Registry.new }

  around { |ex| Textus.with_registry(reg) { ex.run } }

  describe ":resolve_intake" do
    it "registers a resolve_intake hook by name" do
      Textus.on(:resolve_intake, :local_file) do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "ok" }
      end
      out = reg.rpc_callable(:resolve_intake, :local_file).call(store: nil, config: {}, args: {})
      expect(out[:body]).to eq("ok")
    end

    it "accepts a string name and normalizes to a symbol" do
      Textus.on(:resolve_intake, "from_string") do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "s" }
      end
      expect(reg.rpc_names(:resolve_intake)).to include(:from_string)
    end

    it "raises outside with_registry" do
      Thread.new do
        expect do
          Textus.on(:resolve_intake, :naked) { |config:, args:, **| [config, args] }
        end.to raise_error(Textus::UsageError, /no active registry/)
      end.join
    end
  end

  describe ":transform_rows" do
    it "registers a transform_rows hook" do
      Textus.on(:transform_rows, :top2) { |rows:, **| rows.first(2) }
      expect(reg.rpc_callable(:transform_rows, :top2).call(store: nil, rows: [1, 2, 3], config: nil)).to eq([1, 2])
    end
  end

  describe ":validate" do
    it "registers a doctor check" do
      Textus.on(:validate, :always_ok) do |store:|
        [store]
        []
      end
      expect(reg.rpc_callable(:validate, :always_ok).call(store: nil)).to eq([])
    end
  end

  describe ":entry_put with keys: filter" do
    it "registers a pub-sub entry_put hook with key filter" do
      captured = []
      Textus.on(:entry_put, :tap, keys: ["working.*"]) { |key:, **| captured << key }
      reg.listeners(:entry_put, key: "working.x").first[:callable].call(store: nil, key: "working.x", envelope: {})
      expect(captured).to eq(["working.x"])
    end
  end

  describe ":entry_deleted / :entry_refreshed / :build_completed / :proposal_accepted / :file_published" do
    it "registers each pub-sub event" do
      Textus.on(:entry_deleted,      :d) { |key:, **| key }
      Textus.on(:entry_refreshed,    :r) { |key:, envelope:, change:, **| [key, envelope, change] }
      Textus.on(:build_completed,    :b) { |key:, envelope:, sources:, **| [key, envelope, sources] }
      Textus.on(:proposal_accepted,  :a) { |key:, target_key:, **| [key, target_key] }
      Textus.on(:file_published,     :p) { |key:, envelope:, source:, target:, **| [key, envelope, source, target] }

      expect(reg.pubsub_handlers(:entry_deleted).map { _1[:name] }).to include(:d)
      expect(reg.pubsub_handlers(:entry_refreshed).map { _1[:name] }).to include(:r)
      expect(reg.pubsub_handlers(:build_completed).map { _1[:name] }).to include(:b)
      expect(reg.pubsub_handlers(:proposal_accepted).map { _1[:name] }).to include(:a)
      expect(reg.pubsub_handlers(:file_published).map { _1[:name] }).to include(:p)
    end
  end

  describe ":refresh_started / :refresh_failed / :refresh_backgrounded" do
    it "registers each lifecycle event" do
      Textus.on(:refresh_started,      :s) { |key:, mode:, **| [key, mode] }
      Textus.on(:refresh_failed,       :f) { |key:, error_class:, error_message:, **| [key, error_class, error_message] }
      Textus.on(:refresh_backgrounded, :d) { |key:, started_at:, budget_ms:, **| [key, started_at, budget_ms] }

      expect(reg.pubsub_handlers(:refresh_started).map { _1[:name] }).to include(:s)
      expect(reg.pubsub_handlers(:refresh_failed).map { _1[:name] }).to include(:f)
      expect(reg.pubsub_handlers(:refresh_backgrounded).map { _1[:name] }).to include(:d)
    end
  end
end
