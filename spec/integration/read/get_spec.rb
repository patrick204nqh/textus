require "spec_helper"

RSpec.describe Textus::Read::Get do
  include_context "textus_store_fixture"
  include_context "intake doc" # provides `intake_body`; ttl/on_expire vary per example below

  def build_store_with_intake(ttl:, on_expire:)
    intake_store(root, intake_body: intake_body, ttl: ttl, on_expire: on_expire, kind_zone: "canon")
  end

  def build_store_no_intake
    minimal_store(root, kind_zone: "quarantine", key: "feeds.doc", path: "feeds/doc.md")
  end

  def write_doc_in_knowledge(last_fetched_at:)
    File.write(File.join(root, "zones", "knowledge", "doc.md"), <<~MD)
      ---
      name: doc
      last_fetched_at: "#{last_fetched_at}"
      ---
      stored body
    MD
  end

  def write_doc_in_feeds(last_fetched_at: Time.now.utc.iso8601)
    File.write(File.join(root, "zones", "feeds", "doc.md"), <<~MD)
      ---
      name: doc
      last_fetched_at: "#{last_fetched_at}"
      ---
      stored body
    MD
  end

  # get is a pure read (ADR 0089): it annotates freshness but NEVER ingests.

  it "returns the on-disk envelope, observing staleness without ingesting" do
    store = build_store_with_intake(ttl: "1s", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: "2020-01-01T00:00:00Z")
    leaf = File.join(root, "zones", "knowledge", "doc.md")
    before = File.read(leaf)
    ctx = test_ctx(role: "automation")

    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")

    expect(env).not_to be_nil
    expect(env.freshness.stale).to be(true)    # observed stale, NOT refreshed
    expect(env.freshness.fetching).to be(false)
    expect(File.read(leaf)).to eq(before)      # the stale read wrote nothing
  end

  it "returns nil when the key has no envelope" do
    store = build_store_with_intake(ttl: "1h", on_expire: "warn")
    ctx = test_ctx(role: "automation")
    use_case = described_class.new(container: store.container, call: ctx)

    expect(use_case.call("knowledge.doc")).to be_nil
  end

  it "annotates as fresh when no lifecycle policy applies" do
    store = build_store_no_intake
    write_doc_in_feeds
    call = Textus::Call.build(role: "automation")
    env = described_class.new(container: store.container, call: call).call("feeds.doc")
    expect(env.freshness.stale).to be(false)
    expect(env.freshness.fetching).to be(false)
  end

  it "annotates as fresh when the envelope is within TTL" do
    store = build_store_with_intake(ttl: "1h", on_expire: "warn")
    write_doc_in_knowledge(last_fetched_at: Time.now.utc.iso8601)
    ctx = test_ctx(role: "automation")
    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    expect(env.freshness.stale).to be(false)
  end

  it "annotates as stale when past TTL on a refresh policy (still does NOT ingest)" do
    store = build_store_with_intake(ttl: "1s", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    expect(env.freshness.stale).to be(true)
    expect(env.freshness.fetching).to be(false)
  end
end
