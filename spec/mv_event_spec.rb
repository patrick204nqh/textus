# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe ":mv event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.a, path: working/a.md, zone: working }
        - { key: working.b, path: working/b.md, zone: working }
    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.hook(:mv, :log_mv) do |key:, from_key:, to_key:, envelope:, store:|
        $textus_event_log << [:mv, from_key, to_key, envelope["uid"]]
      end
      Textus.hook(:put,     :log_put)    { |key:, envelope:, store:| $textus_event_log << [:put, key] }
      Textus.hook(:deleted, :log_delete) { |key:, store:|             $textus_event_log << [:deleted, key] }
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :mv with from_key, to_key, and envelope after a successful mv" do
    store = Textus::Store.new(root)
    store.put("working.a", meta: { "name" => "a" }, body: "hi", as: "human")
    $textus_event_log.clear
    store.mv("working.a", "working.b", as: "human")
    mv_events = $textus_event_log.select { |e| e[0] == :mv }
    expect(mv_events.length).to eq(1)
    expect(mv_events.first[1]).to eq("working.a")
    expect(mv_events.first[2]).to eq("working.b")
    expect(mv_events.first[3]).to match(/\A[0-9a-f]{16}\z/)
  end

  it "does NOT fire :put or :deleted on mv (mv is its own signal)" do
    store = Textus::Store.new(root)
    store.put("working.a", meta: { "name" => "a" }, body: "hi", as: "human")
    $textus_event_log.clear
    store.mv("working.a", "working.b", as: "human")
    expect($textus_event_log.map(&:first)).not_to include(:put, :deleted)
  end

  it "does NOT fire :mv on dry_run" do
    store = Textus::Store.new(root)
    store.put("working.a", meta: { "name" => "a" }, body: "hi", as: "human")
    $textus_event_log.clear
    store.mv("working.a", "working.b", as: "human", dry_run: true)
    expect($textus_event_log).to be_empty
  end

  it "routes :mv hooks via keys: glob against the destination key" do
    File.write(File.join(root, "hooks/scoped.rb"), <<~RUBY)
      $textus_scoped_log ||= []
      Textus.hook(:mv, :scoped_match,    keys: ["working.b"]) { |to_key:, **| $textus_scoped_log << [:match, to_key] }
      Textus.hook(:mv, :scoped_no_match, keys: ["other.*"])   { |to_key:, **| $textus_scoped_log << [:no_match, to_key] }
    RUBY
    $textus_scoped_log = []
    store = Textus::Store.new(root)
    store.put("working.a", meta: { "name" => "a" }, body: "hi", as: "human")
    store.mv("working.a", "working.b", as: "human")
    expect($textus_scoped_log.map(&:first)).to eq([:match])
  ensure
    $textus_scoped_log = nil
  end
end
# rubocop:enable Style/GlobalVars
