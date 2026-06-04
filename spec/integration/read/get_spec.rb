require "spec_helper"

RSpec.describe Textus::Read::Get do
  include_context "textus_store_fixture"
  include_context "intake doc" # provides `intake_body`; ttl/on_expire vary per example below

  # An orchestrator that must never run: a verifying double with no #execute
  # stubbed raises if the read path calls it (replaces a hand-rolled raise).
  let(:unused_orchestrator) { instance_double(Textus::Write::FetchOrchestrator) }

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

  # ── Pure read branch (fetch: false, the default) ─────────────────────────

  it "pure by default: fetch:false returns the on-disk envelope and never builds an orchestrator" do
    store = build_store_with_intake(ttl: "1s", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    allow(Textus::Write::FetchOrchestrator).to receive(:new).and_call_original
    use_case = described_class.new(container: store.container, call: ctx)

    env = use_case.call("knowledge.doc")
    expect(env).not_to be_nil
    expect(env.freshness.stale).to be(true) # observed stale, NOT fetched
    expect(Textus::Write::FetchOrchestrator).not_to have_received(:new)
  end

  it "returns nil when the key has no envelope (fetch:false)" do
    store = build_store_with_intake(ttl: "1h", on_expire: "warn")
    ctx = test_ctx(role: "automation")
    use_case = described_class.new(container: store.container, call: ctx)

    expect(use_case.call("knowledge.doc")).to be_nil
  end

  it "annotates as fresh when no fetch policy applies (fetch:false)" do
    store = build_store_no_intake
    write_doc_in_feeds
    container = store.container
    call = Textus::Call.build(role: "automation")
    env = described_class.new(container: container, call: call).call("feeds.doc")
    expect(env.freshness.stale).to be(false)
    expect(env.freshness.fetching).to be(false)
  end

  it "annotates as fresh when the envelope is within TTL (fetch:false)" do
    store = build_store_with_intake(ttl: "1h", on_expire: "warn")
    write_doc_in_knowledge(last_fetched_at: Time.now.utc.iso8601)
    ctx = test_ctx(role: "automation")
    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    expect(env.freshness.stale).to be(false)
  end

  it "annotates as stale when the envelope is past TTL (fetch:false — does NOT fetch)" do
    store = build_store_with_intake(ttl: "1s", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    expect(env.freshness.stale).to be(true)
    expect(env.freshness.fetching).to be(false)
  end

  # ── Read-through branch (fetch: true) ────────────────────────────────────

  it "skips orchestrator when verdict is fresh (fetch:true)" do
    store = build_store_with_intake(ttl: "1h", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: Time.now.utc.iso8601)
    ctx = test_ctx(role: "automation")
    use_case = described_class.new(container: store.container, call: ctx, orchestrator: unused_orchestrator)

    env = use_case.call("knowledge.doc", fetch: true)
    expect(env).not_to be_nil
    expect(env.freshness.stale).to be(false)
  end

  it "read-through: fetch:true + stale runs the orchestrator (Skipped outcome)" do
    store = build_store_with_intake(ttl: "1s", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    orch = stub_orchestrator(Textus::Domain::Outcome::Skipped.new)
    use_case = described_class.new(container: store.container, call: ctx, orchestrator: orch)

    env = use_case.call("knowledge.doc", fetch: true)
    expect(env.freshness.stale).to be(true)
    expect(env.freshness.fetching).to be(false)
  end

  it "read-through: fetch:true + stale + Fetched outcome returns a fresh envelope" do
    store = build_store_with_intake(ttl: "1s", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    # Read the stale envelope first, then hand the orchestrator a fresh one.
    stale_env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    fresh_env = stale_env.with(freshness: Textus::Domain::Freshness.build(stale: false, reason: nil, fetching: false))
    orch = stub_orchestrator(Textus::Domain::Outcome::Fetched.new(envelope: fresh_env))
    use_case = described_class.new(container: store.container, call: ctx, orchestrator: orch)

    env = use_case.call("knowledge.doc", fetch: true)
    expect(env.freshness.stale).to be(false)
    expect(env.freshness.fetching).to be(false)
    expect(env.body).to eq(stale_env.body)
  end

  it "annotates fetching=true when orchestrator returns Detached (fetch:true)" do
    store = build_store_with_intake(ttl: "1s", on_expire: "refresh")
    write_doc_in_knowledge(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    orch = stub_orchestrator(Textus::Domain::Outcome::Detached.new)
    use_case = described_class.new(container: store.container, call: ctx, orchestrator: orch)

    env = use_case.call("knowledge.doc", fetch: true)
    expect(env.freshness.fetching).to be(true)
  end

  it "returns nil when the key has no envelope (fetch:true)" do
    store = build_store_with_intake(ttl: "1h", on_expire: "warn")
    ctx = test_ctx(role: "automation")
    use_case = described_class.new(container: store.container, call: ctx, orchestrator: unused_orchestrator)

    expect(use_case.call("knowledge.doc", fetch: true)).to be_nil
  end
end
