# rubocop:disable Style/GlobalVars
require "spec_helper"

RSpec.describe "Lifecycle events" do
  include_context "textus_store_fixture"

  describe "entry put/delete hooks" do
    before do
      FileUtils.mkdir_p(File.join(root, "data/knowledge"))
      FileUtils.mkdir_p(File.join(root, "steps/observe"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes: [{ name: knowledge, kind: canon }]
        entries:
          - { key: knowledge.x, path: data/knowledge/x.md, lane: knowledge, kind: leaf}

      YAML
      File.write(File.join(root, "steps/observe/log_written.rb"), <<~RUBY)
        $textus_event_log ||= []
        Class.new(Textus::Step::Observe) do
          on :entry_written

          def call(key:, **)
            $textus_event_log << [:entry_written, key]
          end
        end
      RUBY
      File.write(File.join(root, "steps/observe/log_deleted.rb"), <<~RUBY)
        $textus_event_log ||= []
        Class.new(Textus::Step::Observe) do
          on :entry_deleted

          def call(key:, **)
            $textus_event_log << [:entry_deleted, key]
          end
        end
      RUBY
      $textus_event_log = []
    end

    after { $textus_event_log = nil }

    it "fires :entry_written after a write" do
      store = Textus::Store.new(root)
      store.as("human").put("knowledge.x", meta: { "name" => "x" }, body: "hi")
      expect($textus_event_log).to include([:entry_written, "knowledge.x"])
    end

    it "fires :entry_deleted after a delete" do
      store = Textus::Store.new(root)
      ops = store.as("human")
      ops.put("knowledge.x", meta: { "name" => "x" }, body: "hi")
      ops.key_delete("knowledge.x")
      expect($textus_event_log).to include([:entry_deleted, "knowledge.x"])
    end

    it "logs hook errors to audit log but does not abort the write" do
      File.write(File.join(root, "steps/observe/boom.rb"), <<~RUBY)
        Class.new(Textus::Step::Observe) do
          on :entry_written

          def call(key:, **)
            _ = key
            raise "bang"
          end
        end
      RUBY
      store = Textus::Store.new(root)
      env = store.as("human").put("knowledge.x", meta: { "name" => "x" }, body: "hi")
      expect(env.body).to eq("hi") # write succeeded
      last = last_audit_row(store)
      expect(last["extras"]["event"]).to eq("entry_written")
      expect(last["extras"]["error"]).to match(/bang/)
    end
  end

  describe "fetch event" do
    before do
      FileUtils.mkdir_p(File.join(root, "data/intake"))
      FileUtils.mkdir_p(File.join(root, "steps/fetch"))
      FileUtils.mkdir_p(File.join(root, "steps/observe"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes: [{ name: intake, kind: machine }]
        entries:
          - key: intake.x
            kind: produced
            path: intake/x.md
            lane: intake
            source: { from: fetch, handler: f }
      YAML
      File.write(File.join(root, "steps/fetch/f.rb"), <<~RUBY)
        Class.new(Textus::Step::Fetch) do
          def call(config:, args:, **)
            _ = config
            _ = args
            { _meta: { "name" => "x" }, body: "v1" }
          end
        end
      RUBY
      File.write(File.join(root, "steps/observe/fetched_tap.rb"), <<~RUBY)
        $log ||= []

        Class.new(Textus::Step::Observe) do
          on :entry_fetched

          def call(key:, change:, **)
            $log << [key, change]
          end
        end
      RUBY
      $log = []
    end

    after { $log = nil }

    # Produce::Acquire::Intake is the internal executor since the `fetch` verb was collapsed
    # (ADR 0079); it fires the same :entry_fetched/:entry_written events.
    def fetch_via(store, key = "intake.x")
      Textus::Produce::Acquire::Intake.new(
        container: store.container, call: Textus::Call.build(role: "automation"),
      ).run(key)
    end

    it "fires :entry_fetched with change=:created on first fetch" do
      store = Textus::Store.new(root)
      fetch_via(store)
      expect($log).to eq([["intake.x", :created]])
    end

    it "fires :entry_fetched with change=:updated when body differs from previous" do
      store = Textus::Store.new(root)
      fetch_via(store)
      File.write(File.join(root, "steps/fetch/f.rb"), <<~RUBY)
        Class.new(Textus::Step::Fetch) do
          def call(config:, args:, **)
            _ = config
            _ = args
            { _meta: { "name" => "x" }, body: "v2" }
          end
        end
      RUBY
      # Re-instantiate to reload hook file from disk (fresh registry)
      store2 = Textus::Store.new(root)
      fetch_via(store2)
      expect($log.last).to eq(["intake.x", :updated])
    end

    it "does NOT fire :entry_fetched when the intake bytes are identical to the previous bytes" do
      store = Textus::Store.new(root)
      fetch_via(store)
      # Rewrite hook with same body so the log is preserved
      # across reload (using ||=) instead of being reset to [].
      File.write(File.join(root, "steps/fetch/f.rb"), <<~RUBY)
        Class.new(Textus::Step::Fetch) do
          def call(config:, args:, **)
            _ = config
            _ = args
            { _meta: { "name" => "x" }, body: "v1" }
          end
        end
      RUBY
      # Re-instantiate to reload hook file from disk
      store2 = Textus::Store.new(root)
      fetch_via(store2)
      # Two fetches with identical action body (both "v1") — only the first
      # should fire :entry_fetched (with :created). The second matches, so no fire.
      expect($log).to eq([["intake.x", :created]])
    end

    it "does NOT double-fire :entry_written when fetch writes (suppress_events:)" do # rubocop:disable RSpec/ExampleLength
      File.write(File.join(root, "steps/fetch/f.rb"), <<~RUBY)
        Class.new(Textus::Step::Fetch) do
          def call(config:, args:, **)
            _ = config
            _ = args
            { _meta: { "name" => "x" }, body: "v" }
          end
        end
      RUBY
      File.write(File.join(root, "steps/observe/fetch_write_log.rb"), <<~RUBY)
        $log = []
        Class.new(Textus::Step::Observe) do
          on :entry_written

          def call(key:, **)
            $log << [:entry_written, key]
          end
        end
      RUBY
      File.write(File.join(root, "steps/observe/fetch_fetched_log.rb"), <<~RUBY)
        $log = []
        Class.new(Textus::Step::Observe) do
          on :entry_fetched

          def call(key:, change:, **)
            $log << [:entry_fetched, key, change]
          end
        end
      RUBY
      $log = []
      store = Textus::Store.new(root)
      fetch_via(store)
      expect($log.count { |e| e[0] == :entry_written }).to eq(0)
      expect($log.count { |e| e[0] == :entry_fetched }).to eq(1)
    end
  end

  describe "build and accept events" do
    before do
      FileUtils.mkdir_p(File.join(root, "data/knowledge"))
      FileUtils.mkdir_p(File.join(root, "data/artifacts"))
      FileUtils.mkdir_p(File.join(root, "steps/observe"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
          - { name: artifacts,  kind: machine }
        entries:
          - { key: knowledge.x, path: data/knowledge/x.md, lane: knowledge, kind: leaf}

          - key: artifacts.summary
            kind: produced
            path: data/artifacts/summary.json
            lane: artifacts
            source:
              from: derive
              select: [knowledge]
              pluck: [name]
            publish:
              - { to: SUMMARY.md, template: summary.mustache }
      YAML
      FileUtils.mkdir_p(File.join(root, "templates"))
      File.write(File.join(root, "templates/summary.mustache"), "{{#rows}}- {{name}}\n{{/rows}}")
      File.write(File.join(root, "data/knowledge/x.md"), "---\nname: x\n---\nhi\n")
      # `$log ||= []` (not `= []`): the hooks file is loaded more than once — the
      # store boot loads it, and the doctor's hooks check (run by `drain` for its
      # health summary) re-loads it. A hard reset would clobber the entry the
      # produce phase appended before drain's post-convergence doctor pass.
      File.write(File.join(root, "steps/observe/entry_produced_log.rb"), <<~RUBY)
        $log ||= []
        Class.new(Textus::Step::Observe) do
          on :entry_produced

          def call(key:, sources:, **)
            $log << [:entry_produced, key, sources]
          end
        end
      RUBY
      $log = []
    end

    after { $log = nil }

    it "fires :entry_produced after Builder materializes an artifacts entry" do
      store = Textus::Store.new(root)
      converge_now(store)
      expect($log).to include([:entry_produced, "artifacts.summary", ["knowledge"]])
    end
  end

  describe "accept event" do
    before do
      FileUtils.mkdir_p(File.join(root, "data/knowledge"))
      FileUtils.mkdir_p(File.join(root, "data/proposals"))
      FileUtils.mkdir_p(File.join(root, "steps/observe"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
          - { name: proposals,  kind: queue }
        entries:
          - { key: knowledge.bob, path: data/knowledge/bob.md, lane: knowledge, kind: leaf}

          - { key: proposals.bob,  path: data/proposals/bob.md,  lane: proposals, kind: leaf}

      YAML
      File.write(File.join(root, "data/proposals/bob.md"), <<~MD)
        ---
        name: bob
        proposal:
          target_key: knowledge.bob
          action: put
        _meta:
          name: bob
        ---
        proposed body
      MD
      File.write(File.join(root, "steps/observe/proposal_accepted_log.rb"), <<~RUBY)
        $log = []
        Class.new(Textus::Step::Observe) do
          on :proposal_accepted

          def call(key:, target_key:, **)
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
      File.write(File.join(root, "steps/observe/proposal_accepted_log.rb"), <<~RUBY)
        Class.new(Textus::Step::Observe) do
          on :proposal_accepted

          def call(key:, target_key:, **)
            _ = key
            _ = target_key
            raise "bang"
          end
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
