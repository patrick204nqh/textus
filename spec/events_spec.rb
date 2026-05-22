# rubocop:disable Style/GlobalVars, RSpec/MultipleDescribes
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Lifecycle events" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.hook(:put,     :log_put)    { |key:, envelope:, store:| $textus_event_log << [:put, key] }
      Textus.hook(:deleted, :log_delete) { |key:, store:| $textus_event_log << [:deleted, key] }
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :put after a write" do
    store = Textus::Store.new(root)
    store.put("working.x", meta: { "name" => "x" }, body: "hi", as: "human")
    expect($textus_event_log).to include([:put, "working.x"])
  end

  it "fires :deleted after a delete" do
    store = Textus::Store.new(root)
    store.put("working.x", meta: { "name" => "x" }, body: "hi", as: "human")
    store.delete("working.x", as: "human")
    expect($textus_event_log).to include([:deleted, "working.x"])
  end

  it "logs hook errors to audit log but does not abort the write" do
    File.write(File.join(root, "hooks/boom.rb"), <<~RUBY)
      Textus.hook(:put, :boom) { |key:, envelope:, store:| raise "bang" }
    RUBY
    store = Textus::Store.new(root)
    env = store.put("working.x", meta: { "name" => "x" }, body: "hi", as: "human")
    expect(env["body"]).to eq("hi") # write succeeded
    last = JSON.parse(File.readlines(File.join(root, "audit.log")).last.chomp)
    expect(last["extras"]["event"]).to eq("put")
    expect(last["extras"]["error"]).to match(/bang/)
  end
end

RSpec.describe "Refresh event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones: [{ name: intake, writable_by: [script] }]
      entries:
        - key: intake.x
          path: intake/x.md
          zone: intake
          intake: { handler: f }
    YAML
    File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
      $log = []
      Textus.hook(:intake, :f) { |store:, config:, args:| { _meta: { "name" => "x" }, body: "v1" } }
      Textus.hook(:refreshed, :tap) { |key:, envelope:, store:, change:| $log << [key, change] }
    RUBY
    $log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $log = nil
  end

  it "fires :refreshed with change=:created on first refresh" do
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    expect($log).to eq([["intake.x", :created]])
  end

  it "fires :refreshed with change=:updated when body differs from previous" do
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
      $log ||= []
      Textus.hook(:intake, :f) { |store:, config:, args:| { _meta: { "name" => "x" }, body: "v2" } }
      Textus.hook(:refreshed, :tap) { |key:, envelope:, store:, change:| $log << [key, change] }
    RUBY
    # Re-instantiate to reload hook file from disk (fresh registry)
    store2 = Textus::Store.new(root)
    Textus::Refresh.call(store2, "intake.x", as: "script")
    expect($log.last).to eq(["intake.x", :updated])
  end

  it "does NOT fire :refreshed when the intake bytes are identical to the previous bytes" do
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    # Rewrite hook with same body so the log is preserved
    # across reload (using ||=) instead of being reset to [].
    File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
      $log ||= []
      Textus.hook(:intake, :f) { |store:, config:, args:| { _meta: { "name" => "x" }, body: "v1" } }
      Textus.hook(:refreshed, :tap) { |key:, envelope:, store:, change:| $log << [key, change] }
    RUBY
    # Re-instantiate to reload hook file from disk
    store2 = Textus::Store.new(root)
    Textus::Refresh.call(store2, "intake.x", as: "script")
    # Two refreshes with identical action body (both "v1") — only the first
    # should fire :refreshed (with :created). The second matches, so no fire.
    expect($log).to eq([["intake.x", :created]])
  end

  it "does NOT double-fire :put when refresh writes (suppress_events:)" do
    File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
      $log = []
      Textus.hook(:intake,   :f) { |store:, config:, args:| { _meta: { "name" => "x" }, body: "v" } }
      Textus.hook(:put,      :p) { |key:, envelope:, store:| $log << [:put, key] }
      Textus.hook(:refreshed, :r) { |key:, envelope:, store:, change:| $log << [:refreshed, key, change] }
    RUBY
    $log = []
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    expect($log.count { |e| e[0] == :put }).to eq(0)
    expect($log.count { |e| e[0] == :refreshed }).to eq(1)
  end
end

RSpec.describe "Build and accept events" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: working.x, path: working/x.md, zone: working }
        - key: derived.summary
          path: derived/summary.md
          zone: derived
          template: summary.mustache
          projection:
            select: [working]
            pluck: [name]
    YAML
    FileUtils.mkdir_p(File.join(root, "templates"))
    File.write(File.join(root, "templates/summary.mustache"), "{{#rows}}- {{name}}\n{{/rows}}")
    File.write(File.join(root, "zones/working/x.md"), "---\nname: x\n---\nhi\n")
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $log = []
      Textus.hook(:built, :t) do |key:, envelope:, store:, sources:|
        $log << [:built, key, sources]
      end
    RUBY
    $log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $log = nil
  end

  it "fires :built after Builder materializes a derived entry" do
    store = Textus::Store.new(root)
    Textus::Composition.writes_build(Textus::Composition.context(store, role: "build")).call
    expect($log).to include([:built, "derived.summary", ["working"]])
  end
end

RSpec.describe "Accept event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human] }
        - { name: pending, writable_by: [ai, human] }
      entries:
        - { key: working.bob, path: working/bob.md, zone: working }
        - { key: pending.bob, path: pending/bob.md, zone: pending }
    YAML
    File.write(File.join(root, "zones/pending/bob.md"), <<~MD)
      ---
      name: bob
      proposal:
        target_key: working.bob
        action: put
      frontmatter:
        name: bob
      ---
      proposed body
    MD
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $log = []
      Textus.hook(:accepted, :t) do |key:, target_key:, store:|
        $log << [:accepted, key, target_key]
      end
    RUBY
    $log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $log = nil
  end

  it "fires :accepted after Proposal.accept completes" do
    store = Textus::Store.new(root)
    store.accept("pending.bob", as: "human")
    expect($log).to include([:accepted, "pending.bob", "working.bob"])
  end

  it "records both target_key and key when an :accepted hook fails" do
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      Textus.hook(:accepted, :boom) { |key:, target_key:, store:| raise "bang" }
    RUBY
    store = Textus::Store.new(root)
    store.accept("pending.bob", as: "human")
    audit_lines = File.readlines(File.join(root, "audit.log")).map { |l| JSON.parse(l.chomp) }
    err = audit_lines.find { |h| h["verb"] == "event_error" }
    expect(err).not_to be_nil
    expect(err["extras"]["event"]).to eq("accepted")
    expect(err["key"]).to eq("pending.bob")
    expect(err["extras"]["target_key"]).to eq("working.bob")
  end
end
# rubocop:enable Style/GlobalVars, RSpec/MultipleDescribes
