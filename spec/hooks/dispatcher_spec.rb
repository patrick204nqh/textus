# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes

require "spec_helper"
require "benchmark"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Hooks::Dispatcher do
  let(:bus) { described_class.new }

  it "calls every subscriber in registration order" do
    seen = []
    bus.subscribe(:entry_put, :a) { |key:, **| seen << [:a, key] }
    bus.subscribe(:entry_put, :b) { |key:, **| seen << [:b, key] }
    bus.publish(:entry_put, store: :view, key: "k", envelope: {})
    expect(seen).to eq([[:a, "k"], [:b, "k"]])
  end

  it "invokes on_error callbacks and continues when a subscriber raises" do
    errors = []
    bus.on_error { |event:, hook:, key:, error:, **| errors << [event, hook, key, error.message] }
    ran = nil
    bus.subscribe(:entry_put, :boom) { |**| raise "bang" }
    bus.subscribe(:entry_put, :ok)   { |key:, **| ran = key }
    bus.publish(:entry_put, store: :view, key: "k", envelope: {})
    expect(ran).to eq("k")
    expect(errors).to eq([[:entry_put, :boom, "k", "bang"]])
  end

  it "filters by key glob when keys: is provided" do
    seen = []
    bus.subscribe(:entry_put, :scoped, keys: "working.*") { |key:, **| seen << key }
    bus.publish(:entry_put, store: :v, key: "working.x", envelope: {})
    bus.publish(:entry_put, store: :v, key: "identity.y", envelope: {})
    expect(seen).to eq(["working.x"])
  end

  it "treats a slow hook as timed_out, not errored" do
    seen_errors = []
    bus.on_error { |hook:, error:, **| seen_errors << [hook, error.class] }
    bus.subscribe(:entry_put, :slow) { |**| sleep 5 }
    bus.subscribe(:entry_put, :ok)   { |**| nil }

    report = nil
    elapsed = Benchmark.realtime do
      report = bus.publish(:entry_put, store: :view, key: "k", envelope: {})
    end

    expect(elapsed).to be < 3.0
    expect(report.timed_out).to eq([:slow])
    expect(report.errored).to eq([])
    expect(report.fired).to eq([:ok])
    expect(seen_errors.map(&:first)).to eq([:slow])
    expect(seen_errors.first.last.name).to eq("Textus::Hooks::Dispatcher::HookTimeout")
  end

  it "returns a FireReport listing every subscriber that fired" do
    bus.subscribe(:entry_put, :a) { |**| nil }
    bus.subscribe(:entry_put, :b) { |**| nil }
    report = bus.publish(:entry_put, store: :view, key: "k", envelope: {})
    expect(report).to be_a(Textus::Hooks::FireReport)
    expect(report.fired).to eq(%i[a b])
    expect(report).to be_ok
  end

  it "returns a non-ok FireReport when a hook errors but does not raise" do
    bus.on_error { |**| nil }
    bus.subscribe(:entry_put, :boom) { |**| raise "bang" }
    bus.subscribe(:entry_put, :ok)   { |**| nil }
    report = bus.publish(:entry_put, store: :view, key: "k", envelope: {})
    expect(report.errored).to eq([:boom])
    expect(report.fired).to eq([:ok])
    expect(report).not_to be_ok
  end

  it "raises the first failure when strict: true after every hook is attempted" do
    audit = []
    bus.on_error { |hook:, **| audit << hook }
    bus.subscribe(:entry_put, :boom1) { |**| raise "first" }
    bus.subscribe(:entry_put, :boom2) { |**| raise "second" }
    expect do
      bus.publish(:entry_put, strict: true, store: :view, key: "k", envelope: {})
    end.to raise_error(RuntimeError, "first")
    expect(audit).to eq(%i[boom1 boom2])
  end
end

RSpec.describe "Hooks::Dispatcher external subscription" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
  end

  it "lets external code subscribe to :put without a hooks/ file" do
    store = Textus::Store.new(root)
    seen = []
    store.bus.register(:entry_put, :external) { |key:, **| seen << key }
    Textus::Operations.for(store, role: "human").put("working.x", meta: { "name" => "x" }, body: "hi")
    expect(seen).to eq(["working.x"])
  end
end
# rubocop:enable RSpec/MultipleDescribes
