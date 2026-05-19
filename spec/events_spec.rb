# rubocop:disable Style/GlobalVars, RSpec/MultipleDescribes
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

  it "logs hook errors to audit log but does not abort the write" do
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

RSpec.describe "Refresh event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones: [{ name: intake, writable_by: [script] }]
      entries:
        - key: intake.x
          path: intake/x.md
          zone: intake
          source: { fetcher: f }
    YAML
    File.write(File.join(root, "extensions/ext.rb"), <<~RUBY)
      $log = []
      Textus.fetcher(:f) { |config:, store:| { frontmatter: { "name" => "x" }, body: "v1" } }
      Textus.hook(:refresh, :tap) { |key:, envelope:, store:, change:| $log << [key, change] }
    RUBY
    $log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $log = nil
  end

  it "fires :refresh with change=:created on first refresh" do
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    expect($log).to eq([["intake.x", :created]])
  end

  it "fires :refresh with change=:updated when body differs from previous" do
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    File.write(File.join(root, "extensions/ext.rb"), <<~RUBY)
      $log ||= []
      Textus.fetcher(:f) { |config:, store:| { frontmatter: { "name" => "x" }, body: "v2" } }
      Textus.hook(:refresh, :tap) { |key:, envelope:, store:, change:| $log << [key, change] }
    RUBY
    # Re-instantiate to reload extension file from disk (fresh registry)
    store2 = Textus::Store.new(root)
    Textus::Refresh.call(store2, "intake.x", as: "script")
    expect($log.last).to eq(["intake.x", :updated])
  end

  it "does NOT fire :refresh when the fetched bytes are identical to the previous bytes" do
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    # Rewrite extension with same fetcher body so the log is preserved
    # across reload (using ||=) instead of being reset to [].
    File.write(File.join(root, "extensions/ext.rb"), <<~RUBY)
      $log ||= []
      Textus.fetcher(:f) { |config:, store:| { frontmatter: { "name" => "x" }, body: "v1" } }
      Textus.hook(:refresh, :tap) { |key:, envelope:, store:, change:| $log << [key, change] }
    RUBY
    # Re-instantiate to reload extension file from disk
    store2 = Textus::Store.new(root)
    Textus::Refresh.call(store2, "intake.x", as: "script")
    # Two refreshes with identical fetcher body (both "v1") — only the first
    # should fire :refresh (with :created). The second matches, so no fire.
    expect($log).to eq([["intake.x", :created]])
  end

  it "does NOT double-fire :put when refresh writes (suppress_events:)" do
    File.write(File.join(root, "extensions/ext.rb"), <<~RUBY)
      $log = []
      Textus.fetcher(:f) { |config:, store:| { frontmatter: { "name" => "x" }, body: "v" } }
      Textus.hook(:put,     :p) { |key:, envelope:, store:| $log << [:put, key] }
      Textus.hook(:refresh, :r) { |key:, envelope:, store:, change:| $log << [:refresh, key, change] }
    RUBY
    $log = []
    store = Textus::Store.new(root)
    Textus::Refresh.call(store, "intake.x", as: "script")
    expect($log.count { |e| e[0] == :put }).to eq(0)
    expect($log.count { |e| e[0] == :refresh }).to eq(1)
  end
end

RSpec.describe "Build and accept events" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
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
    File.write(File.join(root, "extensions/log.rb"), <<~RUBY)
      $log = []
      Textus.hook(:build, :t) do |key:, envelope:, store:, sources:|
        $log << [:build, key, sources]
      end
    RUBY
    $log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $log = nil
  end

  it "fires :build after Builder materializes a derived entry" do
    store = Textus::Store.new(root)
    Textus::Builder.new(store).build
    expect($log).to include([:build, "derived.summary", ["working"]])
  end
end

RSpec.describe "Accept event" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
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
    File.write(File.join(root, "extensions/log.rb"), <<~RUBY)
      $log = []
      Textus.hook(:accept, :t) do |pending_key:, target_key:, store:|
        $log << [:accept, pending_key, target_key]
      end
    RUBY
    $log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $log = nil
  end

  it "fires :accept after Proposal.accept completes" do
    store = Textus::Store.new(root)
    store.accept("pending.bob", as: "human")
    expect($log).to include([:accept, "pending.bob", "working.bob"])
  end

  it "records both target_key and pending_key when an :accept hook fails" do
    File.write(File.join(root, "extensions/log.rb"), <<~RUBY)
      Textus.hook(:accept, :boom) { |pending_key:, target_key:, store:| raise "bang" }
    RUBY
    store = Textus::Store.new(root)
    store.accept("pending.bob", as: "human")
    audit_lines = File.readlines(File.join(root, "audit.log")).map { |l| l.chomp.split("\t") }
    err = audit_lines.find { |c| c[2] == "event_error" }
    expect(err).not_to be_nil
    extras = JSON.parse(err[6])
    expect(extras["event"]).to eq("accept")
    expect(extras["pending_key"]).to eq("pending.bob")
    expect(extras["target_key"]).to eq("working.bob")
  end
end
# rubocop:enable Style/GlobalVars, RSpec/MultipleDescribes
