require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Pulse hook_errors" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/working schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }

  it "returns an empty array when no hooks have failed" do
    result = Textus::Operations.for(store, role: "human").pulse(since: 0)
    expect(result["hook_errors"]).to eq([])
  end

  it "includes a row when a hook errors" do
    store.events.error_log.record(
      seq: 1, event: :entry_put, hook: :sample,
      key: "working.note", error_class: "RuntimeError", error_message: "boom"
    )
    result = Textus::Operations.for(store, role: "human").pulse(since: 0)
    expect(result["hook_errors"].size).to eq(1)
    expect(result["hook_errors"][0]).to include("event" => "entry_put", "hook" => "sample", "error_class" => "RuntimeError")
  end

  it "filters by since seq" do
    store.events.error_log.record(seq: 1, event: :x, hook: :a, key: nil, error_class: "E", error_message: "m")
    store.events.error_log.record(seq: 5, event: :x, hook: :b, key: nil, error_class: "E", error_message: "m")
    result = Textus::Operations.for(store, role: "human").pulse(since: 3)
    expect(result["hook_errors"].map { |r| r["seq"] }).to eq([5])
  end
end
