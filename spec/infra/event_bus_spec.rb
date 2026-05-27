require "spec_helper"

RSpec.describe Textus::Infra::EventBus do
  let(:hook_bus) { Textus::Hooks::Bus.new }
  let(:bus)      { described_class.new(bus: hook_bus) }

  it "routes published events to registered pubsub handlers" do
    received = []
    hook_bus.register(:entry_put, :test_handler) { |key:, **| received << { key: key } }

    bus.publish(:entry_put, key: "some.key", envelope: {}, store: nil)

    expect(received).to eq([{ key: "some.key" }])
  end

  it "calls all registered handlers for the event" do
    calls = []
    hook_bus.register(:entry_put, :handler_a) { |**| calls << :a }
    hook_bus.register(:entry_put, :handler_b) { |**| calls << :b }

    bus.publish(:entry_put, key: "k", envelope: {}, store: nil)

    expect(calls).to contain_exactly(:a, :b)
  end

  it "does not raise when a handler errors; warns instead" do
    hook_bus.register(:entry_put, :boom) { |**| raise "bang" }

    expect do
      bus.publish(:entry_put, key: "k", envelope: {}, store: nil)
    end.not_to raise_error
  end

  it "calls no handlers when no handlers are registered for that event" do
    calls = []
    hook_bus.register(:entry_put, :handler) { |**| calls << :entry_put }

    bus.publish(:entry_deleted, key: "k", store: nil)

    expect(calls).to be_empty
  end
end
