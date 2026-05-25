# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe ":loaded event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.on(:loaded, :log_loaded) { |store:| $textus_event_log << [:loaded, store.store.list.length] }
      Textus.on(:put, :log_put)    { |key:, envelope:, store:| $textus_event_log << [:put, key] }
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :loaded exactly once after Store.new completes" do
    Textus::Store.new(root)
    loaded_events = $textus_event_log.select { |e| e[0] == :loaded }
    expect(loaded_events.length).to eq(1)
  end

  it "fires :loaded with a usable store proxy (reader/writer ready)" do
    Textus::Store.new(root)
    loaded = $textus_event_log.find { |e| e[0] == :loaded }
    expect(loaded[1]).to be_a(Integer) # store.list worked inside the hook
  end

  it "fires :loaded before any subsequent :put" do
    store = Textus::Store.new(root)
    store.put("working.x", meta: { "name" => "x" }, body: "hi", as: "human")
    order = $textus_event_log.map(&:first)
    expect(order.index(:loaded)).to be < order.index(:put)
  end
end
# rubocop:enable Style/GlobalVars
