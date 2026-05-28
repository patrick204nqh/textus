# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Lifecycle events" do
  include_context "textus_store_fixture"

  describe "entry put/delete hooks" do
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
          reg.on(:entry_put, :log_put)    { |key:, **| $textus_event_log << [:entry_put, key] }
          reg.on(:entry_deleted, :log_delete) { |key:, **| $textus_event_log << [:entry_deleted, key] }
        end
      RUBY
      $textus_event_log = []
    end

    after { $textus_event_log = nil }

    it "fires :entry_put after a write" do
      store = Textus::Store.new(root)
      Textus::Operations.for(store, role: "human").put("working.x", meta: { "name" => "x" }, body: "hi")
      expect($textus_event_log).to include([:entry_put, "working.x"])
    end

    it "fires :entry_deleted after a delete" do
      store = Textus::Store.new(root)
      ops = Textus::Operations.for(store, role: "human")
      ops.put("working.x", meta: { "name" => "x" }, body: "hi")
      ops.delete("working.x")
      expect($textus_event_log).to include([:entry_deleted, "working.x"])
    end

    it "logs hook errors to audit log but does not abort the write" do
      File.write(File.join(root, "hooks/boom.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:entry_put, :boom) { |key:, **| raise "bang" }
        end
      RUBY
      store = Textus::Store.new(root)
      env = Textus::Operations.for(store, role: "human").put("working.x", meta: { "name" => "x" }, body: "hi")
      expect(env.body).to eq("hi") # write succeeded
      last = JSON.parse(File.readlines(File.join(root, "audit.log")).last.chomp)
      expect(last["extras"]["event"]).to eq("entry_put")
      expect(last["extras"]["error"]).to match(/bang/)
    end
  end

  describe "refresh event" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/intake"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: intake, write_policy: [runner] }]
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
          reg.on(:entry_refreshed, :tap) { |key:, change:, **| $log << [key, change] }
        end
      RUBY
      $log = []
    end

    after { $log = nil }

    it "fires :entry_refreshed with change=:created on first refresh" do
      store = Textus::Store.new(root)
      Textus::Operations.for(store, role: "runner").refresh("intake.x")
      expect($log).to eq([["intake.x", :created]])
    end

    it "fires :entry_refreshed with change=:updated when body differs from previous" do
      store = Textus::Store.new(root)
      Textus::Operations.for(store, role: "runner").refresh("intake.x")
      File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
        $log ||= []
        Textus.hook do |reg|
          reg.on(:resolve_intake, :f) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "v2" } }
          reg.on(:entry_refreshed, :tap) { |key:, change:, **| $log << [key, change] }
        end
      RUBY
      # Re-instantiate to reload hook file from disk (fresh registry)
      store2 = Textus::Store.new(root)
      Textus::Operations.for(store2, role: "runner").refresh("intake.x")
      expect($log.last).to eq(["intake.x", :updated])
    end

    it "does NOT fire :entry_refreshed when the intake bytes are identical to the previous bytes" do
      store = Textus::Store.new(root)
      Textus::Operations.for(store, role: "runner").refresh("intake.x")
      # Rewrite hook with same body so the log is preserved
      # across reload (using ||=) instead of being reset to [].
      File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
        $log ||= []
        Textus.hook do |reg|
          reg.on(:resolve_intake, :f) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "v1" } }
          reg.on(:entry_refreshed, :tap) { |key:, change:, **| $log << [key, change] }
        end
      RUBY
      # Re-instantiate to reload hook file from disk
      store2 = Textus::Store.new(root)
      Textus::Operations.for(store2, role: "runner").refresh("intake.x")
      # Two refreshes with identical action body (both "v1") — only the first
      # should fire :entry_refreshed (with :created). The second matches, so no fire.
      expect($log).to eq([["intake.x", :created]])
    end

    it "does NOT double-fire :entry_put when refresh writes (suppress_events:)" do
      File.write(File.join(root, "hooks/ext.rb"), <<~RUBY)
        $log = []
        Textus.hook do |reg|
          reg.on(:resolve_intake, :f) { |caps:, config:, args:| { _meta: { "name" => "x" }, body: "v" } }
          reg.on(:entry_put, :p) { |key:, **| $log << [:entry_put, key] }
          reg.on(:entry_refreshed, :r) { |key:, change:, **| $log << [:entry_refreshed, key, change] }
        end
      RUBY
      $log = []
      store = Textus::Store.new(root)
      Textus::Operations.for(store, role: "runner").refresh("intake.x")
      expect($log.count { |e| e[0] == :entry_put }).to eq(0)
      expect($log.count { |e| e[0] == :entry_refreshed }).to eq(1)
    end
  end

  describe "build and accept events" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/working"))
      FileUtils.mkdir_p(File.join(root, "zones/output"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human] }
          - { name: output,  write_policy: [builder] }
        entries:
          - { key: working.x, path: working/x.md, zone: working, kind: leaf}

          - key: output.summary
            kind: derived
            path: output/summary.md
            zone: output
            template: summary.mustache
            compute:
              kind: projection
              select: [working]
              pluck: [name]
      YAML
      FileUtils.mkdir_p(File.join(root, "templates"))
      File.write(File.join(root, "templates/summary.mustache"), "{{#rows}}- {{name}}\n{{/rows}}")
      File.write(File.join(root, "zones/working/x.md"), "---\nname: x\n---\nhi\n")
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

    it "fires :build_completed after Builder materializes an output entry" do
      store = Textus::Store.new(root)
      Textus::Operations.for(store, role: "builder").publish
      expect($log).to include([:build_completed, "output.summary", ["working"]])
    end
  end

  describe "accept event" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/working"))
      FileUtils.mkdir_p(File.join(root, "zones/review"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human] }
          - { name: review,  write_policy: [agent, human] }
        entries:
          - { key: working.bob, path: working/bob.md, zone: working, kind: leaf}

          - { key: review.bob,  path: review/bob.md,  zone: review, kind: leaf}

      YAML
      File.write(File.join(root, "zones/review/bob.md"), <<~MD)
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
      Textus::Operations.for(store, role: "human").accept("review.bob")
      expect($log).to include([:proposal_accepted, "review.bob", "working.bob"])
    end

    it "records both target_key and key when a :proposal_accepted hook fails" do
      File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:proposal_accepted, :boom) { |key:, target_key:, **| raise "bang" }
        end
      RUBY
      store = Textus::Store.new(root)
      Textus::Operations.for(store, role: "human").accept("review.bob")
      audit_lines = File.readlines(File.join(root, "audit.log")).map { |l| JSON.parse(l.chomp) }
      err = audit_lines.find { |h| h["verb"] == "event_error" }
      expect(err).not_to be_nil
      expect(err["extras"]["event"]).to eq("proposal_accepted")
      expect(err["key"]).to eq("review.bob")
      expect(err["extras"]["target_key"]).to eq("working.bob")
    end
  end
end
# rubocop:enable Style/GlobalVars
