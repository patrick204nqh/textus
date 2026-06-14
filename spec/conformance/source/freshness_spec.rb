require "spec_helper"

# Conformance for textus/3 intake source.ttl freshness across the lifecycle:
# the scheduled freshness sweep, the reader's stale-on-get contract, and the
# end-to-end machine-feed fetch path.
RSpec.describe "textus/3 conformance — intake source.ttl freshness" do
  describe "feeds lifecycle via TTL (freshness)" do
    include_context "textus/3 conformance fixture"

    def feeds_row
      store.as(Textus::Role::DEFAULT).freshness(lane: "artifacts")
           .find { |r| r[:key] == "artifacts.feeds.calendar.events" }
    end

    it "marks a never-recorded feeds entry expired" do
      row = feeds_row
      expect(row[:status]).to eq(:expired)
      expect(row[:action]).to eq(:refresh)
    end

    it "marks a feeds entry past its TTL expired" do
      feeds_path = File.join(root, "data/artifacts/feeds/calendar/events.md")
      # Well past the 300s TTL. Wide margin keeps this deterministic regardless of
      # iso8601 second-truncation in last_fetched_at.
      stale_time = (Time.now - 3600).utc.iso8601
      File.write(feeds_path, <<~MD)
        ---
        name: events
        last_fetched_at: "#{stale_time}"
        ---
        body
      MD
      row = feeds_row
      expect(row[:status]).to eq(:expired)
      expect(row[:next_due_at]).not_to be_nil
    end

    it "marks a feeds entry within its TTL fresh" do
      feeds_path = File.join(root, "data/artifacts/feeds/calendar/events.md")
      fresh_time = Time.now.utc.iso8601
      File.write(feeds_path, <<~MD)
        ---
        name: events
        last_fetched_at: "#{fresh_time}"
        ---
        body
      MD
      expect(feeds_row[:status]).to eq(:fresh)
    end
  end

  # Since ADR 0089 the reader NEVER ingests. A stale intake entry (past its
  # source.ttl) is observed stale on `get`; machine-zone freshness is system-pushed
  # via `drain` (scheduled sweep) and `hook run` (event push). These examples
  # pin that contract: a read leaves the intake handler untouched; drain is
  # what re-pulls a stale intake entry (ADR 0093: warn/refresh actions are gone —
  # re-pull is unconditional on the sweep when an intake is past its ttl).
  describe "reader honors intake source.ttl freshness" do
    include_context "textus_store_fixture"

    let(:counting_hook) do
      <<~RUBY
        def call(config:, args:, **)
          Thread.current[:fetch_count] ||= 0
          Thread.current[:fetch_count] += 1
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fresh body" }
        end
      RUBY
    end

    def write_stale_feed
      File.write(
        File.join(root, "data", "feeds", "doc.md"),
        "---\nkey: feeds.doc\nlast_fetched_at: \"2020-01-01T00:00:00Z\"\n---\nold body\n",
      )
    end

    it "a read returns a stale envelope with the flag, never ingesting" do
      Thread.current[:fetch_count] = 0
      store = intake_store(root, intake_body: counting_hook, ttl: "1s")
      write_stale_feed
      envelope = store.as("automation").get("feeds.doc")

      expect(envelope.stale?).to be(true)
      expect(envelope.freshness.reason).to match(/ttl exceeded/)
      expect(envelope.fetching?).to be(false)
      expect(envelope.body || envelope.content).to include("old body")
      expect(Thread.current[:fetch_count]).to eq(0)
    end

    it "drain re-pulls a stale intake entry" do
      Thread.current[:fetch_count] = 0
      store = intake_store(root, intake_body: counting_hook, ttl: "1s")
      write_stale_feed

      converge_now(store)

      expect(Thread.current[:fetch_count]).to eq(1)
      fresh = store.as("automation").get("feeds.doc")
      expect(fresh.stale?).to be(false)
      expect(fresh.body || fresh.content).to include("fresh body")
    end
  end

  describe "feeds.machines end-to-end" do
    around { |ex| Dir.mktmpdir { |d| Dir.chdir(d) { ex.run } } }

    before do
      `git init -q . && git commit -q --allow-empty -m init`
      Textus::Init.run(File.join(Dir.pwd, ".textus"))
    end

    let(:store) { Textus::Store.new(File.join(Dir.pwd, ".textus")) }

    # Produce::Acquire::Intake is the internal executor since the `fetch` verb was collapsed
    # (ADR 0079).
    def fetch_machine(key)
      Textus::Produce::Acquire::Intake.new(
        container: store.container, call: Textus::Call.build(role: "automation"),
      ).run(key)
    end

    # One fetch, all assertions — the scan shells out (brew/runtimes), so we don't
    # repeat it. Guards the allowlist on the ACTUAL scaffolded hook init copies
    # into stores, that the nested `local` leaf is protocol-readable, the tree is
    # gitignored, and nothing leaks secrets.
    it "fetches the local leaf: allowlisted, protocol-readable, AND gitignored" do
      fetch_machine("artifacts.feeds.machines.local") # explicit fetch — never per-turn
      content = store.as("automation").get("artifacts.feeds.machines.local").content

      expect(content.keys).to contain_exactly(
        "git_head", "git_branch", "git_dirty", "repo_root", "captured_at",
        "os", "arch", "ruby_version", "runtimes", "packages", "textus_version", "protocol"
      )
      expect(content["protocol"]).to eq(Textus::PROTOCOL)
      expect(content["textus_version"]).to eq(Textus::VERSION)
      expect(content["runtimes"]).to be_a(Hash) # versions or nil per runtime
      expect(content["packages"]).to be_a(Hash) # counts or nil per manager

      # allowlist discipline: no raw environment, no home-path leak
      expect(content).not_to have_key("env")
      expect(content.to_s).not_to include(ENV.fetch("HOME", "/Users/nobody"))

      expect(`git check-ignore .textus/data/artifacts/feeds/machines/local.yaml`.strip).not_to be_empty
    end

    it "rejects an unknown machine leaf with a clear error" do
      expect { fetch_machine("artifacts.feeds.machines.nope") }
        .to raise_error(/unknown machine: nope/)
    end
  end
end
