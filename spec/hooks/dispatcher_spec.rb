# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Hooks::Dispatcher do
  let(:audit) { instance_double(Textus::Store::AuditLog, append: nil) }
  let(:bus)   { described_class.new(audit_log: audit) }

  it "calls every subscriber in registration order" do
    seen = []
    bus.subscribe(:entry_put, :a) { |key:, **| seen << [:a, key] }
    bus.subscribe(:entry_put, :b) { |key:, **| seen << [:b, key] }
    bus.publish(:entry_put, store: :view, key: "k", envelope: {})
    expect(seen).to eq([[:a, "k"], [:b, "k"]])
  end

  it "audits and continues when a subscriber raises" do
    ran = nil
    bus.subscribe(:entry_put, :boom) { |**| raise "bang" }
    bus.subscribe(:entry_put, :ok)   { |key:, **| ran = key }
    bus.publish(:entry_put, store: :view, key: "k", envelope: {})
    expect(ran).to eq("k")
    expect(audit).to have_received(:append).with(
      hash_including(verb: "event_error", key: "k"),
    )
  end

  it "filters by key glob when keys: is provided" do
    seen = []
    bus.subscribe(:entry_put, :scoped, keys: "working.*") { |key:, **| seen << key }
    bus.publish(:entry_put, store: :v, key: "working.x", envelope: {})
    bus.publish(:entry_put, store: :v, key: "identity.y", envelope: {})
    expect(seen).to eq(["working.x"])
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
    store.bus.subscribe(:entry_put, :external) { |key:, **| seen << key }
    Textus::Operations.for(store, role: "human").writes.put.call("working.x", meta: { "name" => "x" }, body: "hi")
    expect(seen).to eq(["working.x"])
  end
end
# rubocop:enable RSpec/MultipleDescribes
