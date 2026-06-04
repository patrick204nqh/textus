require "spec_helper"

RSpec.describe Textus::Hooks::EventBus do
  let(:bus) { described_class.new }

  it "registers and fires a pubsub event" do
    fired = []
    bus.on(:entry_put, :collector) { |key:, **| fired << key }
    bus.publish(:entry_put, ctx: double("ctx"), key: "a.b", envelope: double("env")) # rubocop:disable RSpec/VerifiedDoubles
    expect(fired).to eq(["a.b"])
  end

  it "rejects an unknown event" do
    expect { bus.on(:not_a_real_event, :x) { nil } }
      .to raise_error(Textus::UsageError, /unknown event/)
  end

  it "rejects an RPC event name on the event bus" do
    expect { bus.on(:resolve_intake, :x) { nil } }
      .to raise_error(Textus::UsageError, /resolve_intake is an RPC event/)
  end

  it "rejects every RPC event in the Catalog (derived, not hard-coded)" do
    bus = Textus::Hooks::EventBus.new
    expect(Textus::Hooks::Catalog::RPC).not_to be_empty
    Textus::Hooks::Catalog::RPC.each_key do |ev|
      expect { bus.on(ev, :_) { |**kwargs| kwargs } }.to raise_error(Textus::UsageError, /is an RPC event/)
    end
  end

  it "filters by key glob" do
    fired = []
    bus.on(:entry_put, :only_a, keys: "a.*") { |key:, **| fired << key }
    bus.publish(:entry_put, ctx: double, key: "a.x", envelope: double)
    bus.publish(:entry_put, ctx: double, key: "b.x", envelope: double)
    expect(fired).to eq(["a.x"])
  end

  it "returns a FireReport listing fired/errored/timed_out" do
    bus.on(:entry_put, :ok) { |**| nil }
    bus.on(:entry_put, :err) { |**| raise "boom" }
    report = bus.publish(:entry_put, ctx: double, key: "k", envelope: double)
    expect(report.fired).to eq([:ok])
    expect(report.errored).to eq([:err])
  end
end
