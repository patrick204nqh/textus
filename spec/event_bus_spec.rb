# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::EventBus do
  let(:audit) { instance_double(Textus::AuditLog, append: nil) }
  let(:bus)   { described_class.new(audit_log: audit) }

  it "calls every subscriber in registration order" do
    seen = []
    bus.subscribe(:put, :a) { |key:, **| seen << [:a, key] }
    bus.subscribe(:put, :b) { |key:, **| seen << [:b, key] }
    bus.publish(:put, store: :view, key: "k", envelope: {})
    expect(seen).to eq([[:a, "k"], [:b, "k"]])
  end

  it "audits and continues when a subscriber raises" do
    ran = nil
    bus.subscribe(:put, :boom) { |**| raise "bang" }
    bus.subscribe(:put, :ok)   { |key:, **| ran = key }
    bus.publish(:put, store: :view, key: "k", envelope: {})
    expect(ran).to eq("k")
    expect(audit).to have_received(:append).with(
      hash_including(verb: "event_error", key: "k"),
    )
  end

  it "filters by key glob when keys: is provided" do
    seen = []
    bus.subscribe(:put, :scoped, keys: "working.*") { |key:, **| seen << key }
    bus.publish(:put, store: :v, key: "working.x", envelope: {})
    bus.publish(:put, store: :v, key: "canon.y",   envelope: {})
    expect(seen).to eq(["working.x"])
  end
end
