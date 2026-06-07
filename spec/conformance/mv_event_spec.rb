# rubocop:disable Style/GlobalVars
require "spec_helper"

RSpec.describe ":entry_renamed event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: knowledge, kind: canon }]
      entries:
        - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf}

        - { key: knowledge.b, path: knowledge/b.md, zone: knowledge, kind: leaf}

    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.hook do |reg|
        reg.on(:entry_renamed, :log_mv) do |from_key:, to_key:, envelope:, **|
          $textus_event_log << [:entry_renamed, from_key, to_key, envelope.uid]
        end
        reg.on(:entry_written, :log_put)    { |key:, **| $textus_event_log << [:entry_written, key] }
        reg.on(:entry_deleted, :log_delete) { |key:, **| $textus_event_log << [:entry_deleted, key] }
      end
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :entry_renamed with from_key, to_key, and envelope after a successful mv" do
    store = Textus::Store.new(root)
    store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
    $textus_event_log.clear
    store.as("human").key_mv("knowledge.a", "knowledge.b")
    mv_events = $textus_event_log.select { |e| e[0] == :entry_renamed }
    expect(mv_events.length).to eq(1)
    expect(mv_events.first[1]).to eq("knowledge.a")
    expect(mv_events.first[2]).to eq("knowledge.b")
    expect(mv_events.first[3]).to match(/\A[0-9a-f]{16}\z/)
  end

  it "does NOT fire :entry_written or :entry_deleted on mv (entry_renamed is its own signal)" do
    store = Textus::Store.new(root)
    store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
    $textus_event_log.clear
    store.as("human").key_mv("knowledge.a", "knowledge.b")
    expect($textus_event_log.map(&:first)).not_to include(:entry_written, :entry_deleted)
  end

  it "does NOT fire :entry_renamed on dry_run" do
    store = Textus::Store.new(root)
    store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
    $textus_event_log.clear
    store.as("human").key_mv("knowledge.a", "knowledge.b", dry_run: true)
    expect($textus_event_log).to be_empty
  end

  it "routes :entry_renamed hooks via keys: glob against the destination key" do
    File.write(File.join(root, "hooks/scoped.rb"), <<~RUBY)
      $textus_scoped_log ||= []
      Textus.hook do |reg|
        reg.on(:entry_renamed, :scoped_match,    keys: ["knowledge.b"]) { |to_key:, **| $textus_scoped_log << [:match, to_key] }
        reg.on(:entry_renamed, :scoped_no_match, keys: ["other.*"])   { |to_key:, **| $textus_scoped_log << [:no_match, to_key] }
      end
    RUBY
    $textus_scoped_log = []
    store = Textus::Store.new(root)
    store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
    store.as("human").key_mv("knowledge.a", "knowledge.b")
    expect($textus_scoped_log.map(&:first)).to eq([:match])
  ensure
    $textus_scoped_log = nil
  end
end
# rubocop:enable Style/GlobalVars
