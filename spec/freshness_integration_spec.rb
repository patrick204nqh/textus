require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Reader honors on_stale policy" do
  def build_store(root, on_stale:, intake_hook_body:)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, runner] }
      entries:
        - key: working.foo
          kind: intake
          path: working/foo.md
          zone: working
          intake:
            handler: test_intake
      rules:
        - match: working.foo
          refresh:
            ttl: 1s
            on_stale: #{on_stale}
    YAML

    File.write(File.join(textus, "zones", "working", "foo.md"), <<~MD)
      ---
      key: working.foo
      last_refreshed_at: "2020-01-01T00:00:00Z"
      ---
      old body
    MD

    File.write(File.join(textus, "hooks", "test_intake.rb"), intake_hook_body)

    Textus::Store.new(textus)
  end

  it "warn: returns stale envelope with flag, does NOT refresh" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.hook do |reg|
          reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
            Thread.current[:refresh_count] ||= 0
            Thread.current[:refresh_count] += 1
            { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "fresh" }
          end
        end
      RUBY

      Thread.current[:refresh_count] = 0
      store = build_store(root, on_stale: "warn", intake_hook_body: hook_body)
      envelope = Textus::Operations.for(store, role: "runner").get_or_refresh("working.foo")

      expect(envelope.stale?).to be(true)
      expect(envelope.freshness.reason).to match(/ttl exceeded/)
      expect(envelope.refreshing?).to be(false)
      expect(Thread.current[:refresh_count]).to eq(0)
    end
  end

  it "sync: blocks for refresh, returns fresh envelope" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.hook do |reg|
          reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
            { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "fresh body" }
          end
        end
      RUBY

      store = build_store(root, on_stale: "sync", intake_hook_body: hook_body)
      envelope = Textus::Operations.for(store, role: "runner").get_or_refresh("working.foo")

      expect(envelope.stale?).to be(false)
      expect(envelope.body || envelope.content).to include("fresh body")
    end
  end

  it "timed_sync: returns stale + refreshing when handler exceeds budget", # rubocop:disable RSpec/ExampleLength
     skip: ("Process.fork unavailable" unless Process.respond_to?(:fork)) do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))

      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, runner] }
        entries:
          - key: working.slow
            kind: intake
            path: working/slow.md
            zone: working
            intake:
              handler: slow_intake
        rules:
          - match: working.slow
            refresh:
              ttl: 1s
              on_stale: timed_sync
              sync_budget_ms: 50
      YAML

      File.write(File.join(textus, "zones", "working", "slow.md"), <<~MD)
        ---
        key: working.slow
        last_refreshed_at: "2020-01-01T00:00:00Z"
        ---
        old
      MD

      File.write(File.join(textus, "hooks", "slow_intake.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :slow_intake) do |caps:, config:, args:|
            sleep 0.5
            { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "fresh-from-child" }
          end
        end
      RUBY

      store = Textus::Store.new(textus)
      t0 = Time.now
      envelope = Textus::Operations.for(store, role: "runner").get_or_refresh("working.slow")
      elapsed = Time.now - t0

      expect(elapsed).to be < 0.4
      expect(envelope.stale?).to be(true)
      expect(envelope.refreshing?).to be(true)

      sleep 1.5
      raw = File.read(File.join(textus, "zones", "working", "slow.md"))
      expect(raw).to include("fresh-from-child")
    end
  end

  it "build materializes using the pure read path (issue #59)" do # rubocop:disable RSpec/ExampleLength
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      FileUtils.mkdir_p(File.join(textus, "zones", "output"))
      FileUtils.mkdir_p(File.join(textus, "templates"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))

      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, runner] }
          - { name: output, write_policy: [builder] }
        entries:
          - key: working.foo
            kind: intake
            path: working/foo.md
            zone: working
            intake:
              handler: test_intake
          - key: output.summary
            kind: derived
            path: output/summary.md
            zone: output
            schema: null
            owner: builder:auto
            compute: { kind: projection, select: working.foo }
            template: echo.mustache
        rules:
          - match: working.foo
            refresh:
              ttl: 1s
              on_stale: timed_sync
              sync_budget_ms: 1
      YAML

      File.write(File.join(textus, "templates", "echo.mustache"), "built {{count}}\n")

      File.write(File.join(textus, "zones", "working", "foo.md"), <<~MD)
        ---
        key: working.foo
        last_refreshed_at: "2020-01-01T00:00:00Z"
        ---
        old body
      MD

      File.write(File.join(textus, "hooks", "test_intake.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
            { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "fresh" }
          end
        end
      RUBY

      orchestrator_calls = []
      allow_any_instance_of(Textus::Application::Refresh::Orchestrator) # rubocop:disable RSpec/AnyInstance
        .to receive(:execute) do |_, *args, **kwargs|
        orchestrator_calls << [args, kwargs]
        raise "orchestrator must not be called during build (issue #59)"
      end

      store = Textus::Store.new(textus)
      Textus::Infra::EventBus.new(bus: store.events)
      ctx = Textus::Operations.for(store, role: "builder").ctx
      build_publish(store, ctx).call

      expect(orchestrator_calls).to be_empty
    end
  end
end
