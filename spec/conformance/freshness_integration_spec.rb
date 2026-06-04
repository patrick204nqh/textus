require "spec_helper"

RSpec.describe "Reader honors lifecycle policy" do
  include_context "textus_store_fixture"

  it "warn: returns stale envelope with flag, does NOT fetch" do
    hook_body = <<~RUBY
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
          Thread.current[:fetch_count] ||= 0
          Thread.current[:fetch_count] += 1
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fresh" }
        end
      end
    RUBY

    Thread.current[:fetch_count] = 0
    store = intake_store(root, intake_body: hook_body, ttl: "1s", on_expire: "warn")
    File.write(
      File.join(root, "zones", "feeds", "doc.md"),
      "---\nkey: feeds.doc\nlast_fetched_at: \"2020-01-01T00:00:00Z\"\n---\nold body\n",
    )
    envelope = store.as("automation").get("feeds.doc")

    expect(envelope.stale?).to be(true)
    expect(envelope.freshness.reason).to match(/ttl exceeded/)
    expect(envelope.fetching?).to be(false)
    expect(Thread.current[:fetch_count]).to eq(0)
  end

  it "sync: blocks for fetch, returns fresh envelope" do
    hook_body = <<~RUBY
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fresh body" }
        end
      end
    RUBY

    store = intake_store(root, intake_body: hook_body, ttl: "1s", on_expire: "refresh")
    File.write(
      File.join(root, "zones", "feeds", "doc.md"),
      "---\nkey: feeds.doc\nlast_fetched_at: \"2020-01-01T00:00:00Z\"\n---\nold body\n",
    )
    envelope = store.as("automation").get("feeds.doc")

    expect(envelope.stale?).to be(false)
    expect(envelope.body || envelope.content).to include("fresh body")
  end

  it "timed_sync: returns stale + fetching when handler exceeds budget", # rubocop:disable RSpec/ExampleLength
     skip: ("Process.fork unavailable" unless Process.respond_to?(:fork)) do
    timed_root = File.join(tmp, "timed")
    FileUtils.mkdir_p(File.join(timed_root, "zones", "feeds"))
    FileUtils.mkdir_p(File.join(timed_root, "hooks"))

    File.write(File.join(timed_root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: quarantine }
      entries:
        - key: feeds.slow
          kind: intake
          path: feeds/slow.md
          zone: feeds
          intake:
            handler: slow_intake
      rules:
        - match: feeds.slow
          lifecycle:
            ttl: 1s
            on_expire: refresh
            budget_ms: 50
    YAML

    File.write(File.join(timed_root, "zones", "feeds", "slow.md"), <<~MD)
      ---
      key: feeds.slow
      last_fetched_at: "2020-01-01T00:00:00Z"
      ---
      old
    MD

    File.write(File.join(timed_root, "hooks", "slow_intake.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :slow_intake) do |caps:, config:, args:|
          sleep 0.5
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fresh-from-child" }
        end
      end
    RUBY

    store = Textus::Store.new(timed_root)
    t0 = Time.now
    envelope = store.as("automation").get("feeds.slow")
    elapsed = Time.now - t0

    expect(elapsed).to be < 0.4
    expect(envelope.stale?).to be(true)
    expect(envelope.fetching?).to be(true)

    sleep 1.5
    raw = File.read(File.join(timed_root, "zones", "feeds", "slow.md"))
    expect(raw).to include("fresh-from-child")
  end

  it "build materializes using the pure read path (issue #59)" do # rubocop:disable RSpec/ExampleLength
    build_root = File.join(tmp, "build")
    FileUtils.mkdir_p(File.join(build_root, "zones", "feeds"))
    FileUtils.mkdir_p(File.join(build_root, "zones", "artifacts"))
    FileUtils.mkdir_p(File.join(build_root, "templates"))
    FileUtils.mkdir_p(File.join(build_root, "hooks"))

    File.write(File.join(build_root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: quarantine }
        - { name: artifacts, kind: derived }
      entries:
        - key: feeds.foo
          kind: intake
          path: feeds/foo.md
          zone: feeds
          intake:
            handler: test_intake
        - key: artifacts.summary
          kind: derived
          path: artifacts/summary.md
          zone: artifacts
          owner: automation:auto
          compute: { kind: projection, select: feeds.foo }
          template: echo.mustache
      rules:
        - match: feeds.foo
          lifecycle:
            ttl: 1s
            on_expire: refresh
            budget_ms: 1
    YAML

    File.write(File.join(build_root, "templates", "echo.mustache"), "built {{count}}\n")

    File.write(File.join(build_root, "zones", "feeds", "foo.md"), <<~MD)
      ---
      key: feeds.foo
      last_fetched_at: "2020-01-01T00:00:00Z"
      ---
      old body
    MD

    File.write(File.join(build_root, "hooks", "test_intake.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fresh" }
        end
      end
    RUBY

    orchestrator_calls = []
    allow_any_instance_of(Textus::Write::FetchOrchestrator) # rubocop:disable RSpec/AnyInstance
      .to receive(:execute) do |_, *args, **kwargs|
      orchestrator_calls << [args, kwargs]
      raise "orchestrator must not be called during build (issue #59)"
    end

    store = Textus::Store.new(build_root)
    store.as("automation").build

    expect(orchestrator_calls).to be_empty
  end
end
