# rubocop:disable Style/GlobalVars
require "spec_helper"

RSpec.describe "Lifecycle events" do
  include_context "textus_store_fixture"

  describe "entry put/delete hooks" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: knowledge, kind: canon }]
        entries:
          - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf}

      YAML
      File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
        $textus_event_log ||= []
        Textus.hook do |reg|
          reg.on(:entry_put, :log_put)    { |key:, **| $textus_event_log << [:entry_put, key] }
          reg.on(:entry_deleted, :log_delete) { |key:, **| $textus_event_log << [:entry_deleted, key] }
        end
      RUBY
      $textus_event_log = []
    end

    after { $textus_event_log = nil }

    it "fires :entry_put after a write" do
      store = Textus::Store.new(root)
      store.as("human").put("knowledge.x", meta: { "name" => "x" }, body: "hi")
      expect($textus_event_log).to include([:entry_put, "knowledge.x"])
    end

    it "fires :entry_deleted after a delete" do
      store = Textus::Store.new(root)
      ops = store.as("human")
      ops.put("knowledge.x", meta: { "name" => "x" }, body: "hi")
      ops.delete("knowledge.x")
      expect($textus_event_log).to include([:entry_deleted, "knowledge.x"])
    end

    it "logs hook errors to audit log but does not abort the write" do
      File.write(File.join(root, "hooks/boom.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:entry_put, :boom) { |key:, **| raise "bang" }
        end
      RUBY
      store = Textus::Store.new(root)
      env = store.as("human").put("knowledge.x", meta: { "name" => "x" }, body: "hi")
      expect(env.body).to eq("hi") # write succeeded
      last = last_audit_row(store)
      expect(last["extras"]["event"]).to eq("entry_put")
      expect(last["extras"]["error"]).to match(/bang/)
    end
  end

  describe "fetch event" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/intake"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: intake, kind: quarantine }]
        entries:
          - key: intake.x
            kind: intake
            path: intake/x.md
            zone: intake
            intake: { handler: f }
      YAML
      File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
        $log = []
        Textus.hook do |reg|
          reg.on(:resolve_intake, :f) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "v1" } }
          reg.on(:entry_fetched, :tap) { |key:, change:, **| $log << [key, change] }
        end
      RUBY
      $log = []
    end

    after { $log = nil }

    it "fires :entry_fetched with change=:created on first fetch" do
      store = Textus::Store.new(root)
      store.as("automation").fetch("intake.x")
      expect($log).to eq([["intake.x", :created]])
    end

    it "fires :entry_fetched with change=:updated when body differs from previous" do
      store = Textus::Store.new(root)
      store.as("automation").fetch("intake.x")
      File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
        $log ||= []
        Textus.hook do |reg|
          reg.on(:resolve_intake, :f) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "v2" } }
          reg.on(:entry_fetched, :tap) { |key:, change:, **| $log << [key, change] }
        end
      RUBY
      # Re-instantiate to reload hook file from disk (fresh registry)
      store2 = Textus::Store.new(root)
      store2.as("automation").fetch("intake.x")
      expect($log.last).to eq(["intake.x", :updated])
    end

    it "does NOT fire :entry_fetched when the intake bytes are identical to the previous bytes" do
      store = Textus::Store.new(root)
      store.as("automation").fetch("intake.x")
      # Rewrite hook with same body so the log is preserved
      # across reload (using ||=) instead of being reset to [].
      File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
        $log ||= []
        Textus.hook do |reg|
          reg.on(:resolve_intake, :f) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "v1" } }
          reg.on(:entry_fetched, :tap) { |key:, change:, **| $log << [key, change] }
        end
      RUBY
      # Re-instantiate to reload hook file from disk
      store2 = Textus::Store.new(root)
      store2.as("automation").fetch("intake.x")
      # Two fetches with identical action body (both "v1") — only the first
      # should fire :entry_fetched (with :created). The second matches, so no fire.
      expect($log).to eq([["intake.x", :created]])
    end

    it "does NOT double-fire :entry_put when fetch writes (suppress_events:)" do
      File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
        $log = []
        Textus.hook do |reg|
          reg.on(:resolve_intake, :f) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "v" } }
          reg.on(:entry_put, :p) { |key:, **| $log << [:entry_put, key] }
          reg.on(:entry_fetched, :r) { |key:, change:, **| $log << [:entry_fetched, key, change] }
        end
      RUBY
      $log = []
      store = Textus::Store.new(root)
      store.as("automation").fetch("intake.x")
      expect($log.count { |e| e[0] == :entry_put }).to eq(0)
      expect($log.count { |e| e[0] == :entry_fetched }).to eq(1)
    end
  end

  describe "build and accept events" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: artifacts,  kind: derived }
        entries:
          - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf}

          - key: artifacts.summary
            kind: derived
            path: artifacts/summary.md
            zone: artifacts
            template: summary.mustache
            compute:
              kind: projection
              select: [knowledge]
              pluck: [name]
      YAML
      FileUtils.mkdir_p(File.join(root, "templates"))
      File.write(File.join(root, "templates/summary.mustache"), "{{#rows}}- {{name}}\n{{/rows}}")
      File.write(File.join(root, "zones/knowledge/x.md"), "---\nname: x\n---\nhi\n")
      File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
        $log = []
        Textus.hook do |reg|
          reg.on(:build_completed, :t) do |key:, sources:, **|
            $log << [:build_completed, key, sources]
          end
        end
      RUBY
      $log = []
    end

    after { $log = nil }

    it "fires :build_completed after Builder materializes an artifacts entry" do
      store = Textus::Store.new(root)
      store.as("automation").publish
      expect($log).to include([:build_completed, "artifacts.summary", ["knowledge"]])
    end
  end

  describe "accept event" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      FileUtils.mkdir_p(File.join(root, "zones/proposals"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: proposals,  kind: queue }
        entries:
          - { key: knowledge.bob, path: knowledge/bob.md, zone: knowledge, kind: leaf}

          - { key: proposals.bob,  path: proposals/bob.md,  zone: proposals, kind: leaf}

      YAML
      File.write(File.join(root, "zones/proposals/bob.md"), <<~MD)
        ---
        name: bob
        proposal:
          target_key: knowledge.bob
          action: put
        frontmatter:
          name: bob
        ---
        proposed body
      MD
      File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
        $log = []
        Textus.hook do |reg|
          reg.on(:proposal_accepted, :t) do |key:, target_key:, **|
            $log << [:proposal_accepted, key, target_key]
          end
        end
      RUBY
      $log = []
    end

    after { $log = nil }

    it "fires :proposal_accepted after Proposal.accept completes" do
      store = Textus::Store.new(root)
      store.as("human").accept("proposals.bob")
      expect($log).to include([:proposal_accepted, "proposals.bob", "knowledge.bob"])
    end

    it "records both target_key and key when a :proposal_accepted hook fails" do
      File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:proposal_accepted, :boom) { |key:, target_key:, **| raise "bang" }
        end
      RUBY
      store = Textus::Store.new(root)
      store.as("human").accept("proposals.bob")
      audit_lines = File.readlines(audit_log_path(root)).map { |l| JSON.parse(l.chomp) }
      err = audit_lines.find { |h| h["verb"] == "event_error" }
      expect(err).not_to be_nil
      expect(err["extras"]["event"]).to eq("proposal_accepted")
      expect(err["key"]).to eq("proposals.bob")
      expect(err["extras"]["target_key"]).to eq("knowledge.bob")
    end
  end
end
# rubocop:enable Style/GlobalVars
