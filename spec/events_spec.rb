# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Lifecycle events" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    File.write(File.join(root, "extensions/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.hook(:put, :log_put)       { |key:, envelope:, store:| $textus_event_log << [:put, key] }
      Textus.hook(:delete, :log_delete) { |key:, store:| $textus_event_log << [:delete, key] }
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :put after a write" do
    store = Textus::Store.new(root)
    store.put("working.x", frontmatter: { "name" => "x" }, body: "hi", as: "human")
    expect($textus_event_log).to include([:put, "working.x"])
  end

  it "fires :delete after a delete" do
    store = Textus::Store.new(root)
    store.put("working.x", frontmatter: { "name" => "x" }, body: "hi", as: "human")
    store.delete("working.x", as: "human")
    expect($textus_event_log).to include([:delete, "working.x"])
  end

  it "logs hook errors to audit log but does not abort the write", pending: "audit extras column lands in Task 12" do
    File.write(File.join(root, "extensions/boom.rb"), <<~RUBY)
      Textus.hook(:put, :boom) { |key:, envelope:, store:| raise "bang" }
    RUBY
    store = Textus::Store.new(root)
    env = store.put("working.x", frontmatter: { "name" => "x" }, body: "hi", as: "human")
    expect(env["body"]).to eq("hi") # write succeeded
    last = File.readlines(File.join(root, "audit.log")).last.chomp.split("\t")
    extras = JSON.parse(last[6])
    expect(extras["event"]).to eq("put")
    expect(extras["error"]).to match(/bang/)
  end
end
# rubocop:enable Style/GlobalVars
