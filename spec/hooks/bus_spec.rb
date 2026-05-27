require "spec_helper"

RSpec.describe Textus::Hooks::Bus do
  let(:bus) { described_class.new }

  describe "RPC mode" do
    it "registers and returns a callable" do
      bus.register(:transform_rows, :my_t) do |store:, rows:, config:|
        [store, config]
        rows
      end
      callable = bus.rpc_callable(:transform_rows, :my_t)
      expect(callable.call(store: :s, rows: [1], config: {})).to eq([1])
    end

    it "refuses duplicate RPC names" do
      bus.register(:transform_rows, :dup) do |store:, rows:, config:|
        [store, config]
        rows
      end
      expect do
        bus.register(:transform_rows, :dup) do |store:, rows:, config:|
          [store, config]
          rows
        end
      end.to raise_error(Textus::UsageError, /already registered/)
    end

    it "raises UsageError for unknown rpc name" do
      expect { bus.rpc_callable(:transform_rows, :missing) }
        .to raise_error(Textus::UsageError, /unknown transform_rows/)
    end
  end

  describe "pubsub mode" do
    it "delivers events to multiple handlers" do
      seen = []
      bus.register(:entry_put, :a) do |store:, key:, envelope:|
        [store, envelope]
        seen << [:a, key]
      end
      bus.register(:entry_put, :b) do |store:, key:, envelope:|
        [store, envelope]
        seen << [:b, key]
      end
      bus.publish(:entry_put, store: :s, key: "x", envelope: nil)
      expect(seen).to contain_exactly([:a, "x"], [:b, "x"])
    end

    it "filters by key glob" do
      seen = []
      bus.register(:entry_put, :g, keys: "working.*") do |store:, key:, envelope:|
        [store, envelope]
        seen << key
      end
      bus.publish(:entry_put, store: :s, key: "working.notes", envelope: nil)
      bus.publish(:entry_put, store: :s, key: "output.x", envelope: nil)
      expect(seen).to eq(["working.notes"])
    end

    it "reports timeouts via on_error and FireReport" do
      err = nil
      bus.on_error do |event:, hook:, key:, kwargs:, error:|
        [event, hook, key, kwargs]
        err = error
      end
      bus.register(:entry_put, :slow) { |**| sleep 5 }
      report = bus.publish(:entry_put, store: :s, key: "x", envelope: nil)
      expect(report.timed_out).to eq([:slow])
      expect(err).to be_a(Textus::Hooks::Bus::HookTimeout)
    end

    it "in strict mode re-raises the first hook error" do
      bus.register(:entry_put, :boom) { |**| raise "nope" }
      expect do
        bus.publish(:entry_put, strict: true, store: :s, key: "x", envelope: nil)
      end.to raise_error("nope")
    end
  end

  describe "event shape validation" do
    it "rejects unknown events" do
      expect { bus.register(:nope, :x) { nil } }
        .to raise_error(Textus::UsageError, /unknown event/)
    end

    it "rejects handlers missing required kwargs" do
      expect do
        bus.register(:entry_put, :bad) { |key:| key } # missing :store, :envelope
      end.to raise_error(Textus::UsageError, /must accept kwargs/)
    end
  end
end
