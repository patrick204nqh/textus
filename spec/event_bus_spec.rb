# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::EventBus do
  let(:audit) { instance_double(Textus::Store::AuditLog, append: nil) }
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

RSpec.describe "EventBus external subscription" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  it "lets external code subscribe to :put without a hooks/ file" do
    store = Textus::Store.new(root)
    seen = []
    store.bus.subscribe(:put, :external) { |key:, **| seen << key }
    store.put("working.x", meta: { "name" => "x" }, body: "hi", as: "human")
    expect(seen).to eq(["working.x"])
  end
end
# rubocop:enable RSpec/MultipleDescribes
