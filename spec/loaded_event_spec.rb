# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe ":store_loaded event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: working, write_policy: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working, kind: leaf}

    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.hook do |reg|
        reg.on(:store_loaded, :log_loaded) do |ctx:|
          list = ctx.list
          $textus_event_log << [:store_loaded, list.length]
        end
        reg.on(:entry_put, :log_put) { |key:, **| $textus_event_log << [:entry_put, key] }
      end
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :store_loaded exactly once after Store.new completes" do
    Textus::Store.new(root)
    loaded_events = $textus_event_log.select { |e| e[0] == :store_loaded }
    expect(loaded_events.length).to eq(1)
  end

  it "fires :store_loaded with a usable store proxy (reader/writer ready)" do
    Textus::Store.new(root)
    loaded = $textus_event_log.find { |e| e[0] == :store_loaded }
    expect(loaded[1]).to be_a(Integer) # store.list worked inside the hook
  end

  it "fires :store_loaded before any subsequent :entry_put" do
    store = Textus::Store.new(root)
    store.session(role: "human").put("working.x", meta: { "name" => "x" }, body: "hi")
    order = $textus_event_log.map(&:first)
    expect(order.index(:store_loaded)).to be < order.index(:entry_put)
  end
end
# rubocop:enable Style/GlobalVars
