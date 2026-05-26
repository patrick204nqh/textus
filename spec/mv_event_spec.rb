# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe ":entry_renamed event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [human] }]
      entries:
        - { key: working.a, path: working/a.md, zone: working }
        - { key: working.b, path: working/b.md, zone: working }
    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.on(:entry_renamed, :log_mv) do |key:, from_key:, to_key:, envelope:, store:|
        $textus_event_log << [:entry_renamed, from_key, to_key, envelope.uid]
      end
      Textus.on(:entry_put, :log_put)    { |key:, envelope:, store:| $textus_event_log << [:entry_put, key] }
      Textus.on(:entry_deleted, :log_delete) { |key:, store:|             $textus_event_log << [:entry_deleted, key] }
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :entry_renamed with from_key, to_key, and envelope after a successful mv" do
    store = Textus::Store.new(root)
    Textus::Operations.for(store, role: "human").put("working.a", meta: { "name" => "a" }, body: "hi")
    $textus_event_log.clear
    Textus::Operations.for(store, role: "human").mv("working.a", "working.b")
    mv_events = $textus_event_log.select { |e| e[0] == :entry_renamed }
    expect(mv_events.length).to eq(1)
    expect(mv_events.first[1]).to eq("working.a")
    expect(mv_events.first[2]).to eq("working.b")
    expect(mv_events.first[3]).to match(/\A[0-9a-f]{16}\z/)
  end

  it "does NOT fire :entry_put or :entry_deleted on mv (entry_renamed is its own signal)" do
    store = Textus::Store.new(root)
    Textus::Operations.for(store, role: "human").put("working.a", meta: { "name" => "a" }, body: "hi")
    $textus_event_log.clear
    Textus::Operations.for(store, role: "human").mv("working.a", "working.b")
    expect($textus_event_log.map(&:first)).not_to include(:entry_put, :entry_deleted)
  end

  it "does NOT fire :entry_renamed on dry_run" do
    store = Textus::Store.new(root)
    Textus::Operations.for(store, role: "human").put("working.a", meta: { "name" => "a" }, body: "hi")
    $textus_event_log.clear
    Textus::Operations.for(store, role: "human").mv("working.a", "working.b", dry_run: true)
    expect($textus_event_log).to be_empty
  end

  it "routes :entry_renamed hooks via keys: glob against the destination key" do
    File.write(File.join(root, "hooks/scoped.rb"), <<~RUBY)
      $textus_scoped_log ||= []
      Textus.on(:entry_renamed, :scoped_match,    keys: ["working.b"]) { |to_key:, **| $textus_scoped_log << [:match, to_key] }
      Textus.on(:entry_renamed, :scoped_no_match, keys: ["other.*"])   { |to_key:, **| $textus_scoped_log << [:no_match, to_key] }
    RUBY
    $textus_scoped_log = []
    store = Textus::Store.new(root)
    Textus::Operations.for(store, role: "human").put("working.a", meta: { "name" => "a" }, body: "hi")
    Textus::Operations.for(store, role: "human").mv("working.a", "working.b")
    expect($textus_scoped_log.map(&:first)).to eq([:match])
  ensure
    $textus_scoped_log = nil
  end
end
# rubocop:enable Style/GlobalVars
