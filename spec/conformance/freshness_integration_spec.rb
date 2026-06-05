require "spec_helper"

# Since ADR 0089 the reader NEVER ingests, regardless of on_expire. A stale
# entry is observed stale on `get`; quarantine freshness is system-pushed via
# `reconcile` (scheduled sweep) and `hook run` (event push). These examples pin
# that contract: a read leaves the intake handler untouched; reconcile is what
# re-pulls a stale `on_expire: refresh` entry.
RSpec.describe "Reader honors lifecycle policy" do
  include_context "textus_store_fixture"

  let(:counting_hook) do
    <<~RUBY
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
          Thread.current[:fetch_count] ||= 0
          Thread.current[:fetch_count] += 1
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fresh body" }
        end
      end
    RUBY
  end

  def write_stale_feed
    File.write(
      File.join(root, "zones", "feeds", "doc.md"),
      "---\nkey: feeds.doc\nlast_fetched_at: \"2020-01-01T00:00:00Z\"\n---\nold body\n",
    )
  end

  it "warn: returns a stale envelope with the flag, never ingesting" do
    Thread.current[:fetch_count] = 0
    store = intake_store(root, intake_body: counting_hook, ttl: "1s", on_expire: "warn")
    write_stale_feed
    envelope = store.as("automation").get("feeds.doc")

    expect(envelope.stale?).to be(true)
    expect(envelope.freshness.reason).to match(/ttl exceeded/)
    expect(envelope.fetching?).to be(false)
    expect(Thread.current[:fetch_count]).to eq(0)
  end

  it "refresh: a read stays stale and does NOT ingest (ADR 0089)" do
    Thread.current[:fetch_count] = 0
    store = intake_store(root, intake_body: counting_hook, ttl: "1s", on_expire: "refresh")
    write_stale_feed
    envelope = store.as("automation").get("feeds.doc")

    expect(envelope.stale?).to be(true)
    expect(envelope.body || envelope.content).to include("old body")
    expect(Thread.current[:fetch_count]).to eq(0)
  end

  it "reconcile is what re-pulls a stale refresh entry" do
    Thread.current[:fetch_count] = 0
    store = intake_store(root, intake_body: counting_hook, ttl: "1s", on_expire: "refresh")
    write_stale_feed

    store.as("automation").reconcile

    expect(Thread.current[:fetch_count]).to eq(1)
    fresh = store.as("automation").get("feeds.doc")
    expect(fresh.stale?).to be(false)
    expect(fresh.body || fresh.content).to include("fresh body")
  end
end
