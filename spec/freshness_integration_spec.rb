require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Reader honors on_stale policy" do
  def build_store(root, on_stale:, intake_hook_body:)
    textus = File.join(root, ".textus")
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, script] }
      entries:
        - key: working.foo
          path: working/foo.md
          zone: working
          intake:
            handler: test_intake
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
        Textus.intake(:test_intake) do |store:, config:, args:|
          Thread.current[:refresh_count] ||= 0
          Thread.current[:refresh_count] += 1
          { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "fresh" }
        end
      RUBY

      Thread.current[:refresh_count] = 0
      store = build_store(root, on_stale: "warn", intake_hook_body: hook_body)
      envelope = store.get("working.foo")

      expect(envelope["stale"]).to be(true)
      expect(envelope["stale_reason"]).to match(/ttl exceeded/)
      expect(envelope["refreshing"]).to be(false)
      expect(Thread.current[:refresh_count]).to eq(0)
    end
  end

  it "sync: blocks for refresh, returns fresh envelope" do
    Dir.mktmpdir do |root|
      hook_body = <<~RUBY
        Textus.intake(:test_intake) do |store:, config:, args:|
          { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "fresh body" }
        end
      RUBY

      store = build_store(root, on_stale: "sync", intake_hook_body: hook_body)
      envelope = store.get("working.foo")

      expect(envelope["stale"]).to be(false)
      expect(envelope["body"] || envelope["content"]).to include("fresh body")
    end
  end

  it "timed_sync: returns stale + refreshing when handler exceeds budget", # rubocop:disable RSpec/ExampleLength
     skip: ("Process.fork unavailable" unless Process.respond_to?(:fork)) do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))

      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: working, writable_by: [human, script] }
        entries:
          - key: working.slow
            path: working/slow.md
            zone: working
            intake:
              handler: slow_intake
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
        Textus.intake(:slow_intake) do |store:, config:, args:|
          sleep 0.5
          { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "fresh-from-child" }
        end
      RUBY

      store = Textus::Store.new(textus)
      t0 = Time.now
      envelope = store.get("working.slow")
      elapsed = Time.now - t0

      expect(elapsed).to be < 0.4
      expect(envelope["stale"]).to be(true)
      expect(envelope["refreshing"]).to be(true)

      sleep 1.5
      raw = File.read(File.join(textus, "zones", "working", "slow.md"))
      expect(raw).to include("fresh-from-child")
    end
  end
end
