require "spec_helper"

RSpec.describe Textus::Read::Get do
  include_context "textus_store_fixture"

  let(:intake_body) do
    <<~RUBY
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) { |caps:, config:, args:| { _meta: { "name" => "doc" }, body: "fresh" } }
      end
    RUBY
  end
  let(:fake_orchestrator_returning) do
    lambda do |outcome|
      Class.new do
        define_method(:execute) do |_action, key: nil|
          _ = key
          outcome
        end
      end.new
    end
  end

  def build_store_with_intake(ttl:, on_stale:)
    intake_store(root, intake_body: intake_body, ttl: ttl, on_stale: on_stale, kind_zone: "canon")
  end

  def write_doc(last_fetched_at:)
    File.write(File.join(root, "zones", "knowledge", "doc.md"), <<~MD)
      ---
      name: doc
      last_fetched_at: "#{last_fetched_at}"
      ---
      stored body
    MD
  end

  it "delegates to GetEntry and skips orchestrator when verdict is fresh" do
    store = build_store_with_intake(ttl: "1h", on_stale: "warn")
    write_doc(last_fetched_at: Time.now.utc.iso8601)
    ctx = test_ctx(role: "automation")
    pure_get = Textus::Read::GetEntry.new(container: store.container, call: ctx)
    orch = Class.new { def execute(*) = raise("must not call") }.new
    use_case = described_class.new(container: store.container, call: ctx, get: pure_get,
                                   orchestrator: orch)

    env = use_case.call("knowledge.doc")
    expect(env).not_to be_nil
    expect(env.freshness.stale).to be(false)
  end

  it "runs the orchestrator when the verdict is stale (Skipped outcome)" do
    store = build_store_with_intake(ttl: "1s", on_stale: "warn")
    write_doc(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    pure_get = Textus::Read::GetEntry.new(container: store.container, call: ctx)
    orch = fake_orchestrator_returning.call(Textus::Domain::Outcome::Skipped.new)
    use_case = described_class.new(container: store.container, call: ctx, get: pure_get,
                                   orchestrator: orch)

    env = use_case.call("knowledge.doc")
    expect(env.freshness.stale).to be(true)
    expect(env.freshness.fetching).to be(false)
  end

  it "annotates fetching=true when orchestrator returns Detached" do
    store = build_store_with_intake(ttl: "1s", on_stale: "timed_sync")
    write_doc(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    pure_get = Textus::Read::GetEntry.new(container: store.container, call: ctx)
    orch = fake_orchestrator_returning.call(Textus::Domain::Outcome::Detached.new)
    use_case = described_class.new(container: store.container, call: ctx, get: pure_get,
                                   orchestrator: orch)

    env = use_case.call("knowledge.doc")
    expect(env.freshness.fetching).to be(true)
  end

  it "returns nil when the key has no envelope" do
    store = build_store_with_intake(ttl: "1h", on_stale: "warn")
    ctx = test_ctx(role: "automation")
    pure_get = Textus::Read::GetEntry.new(container: store.container, call: ctx)
    orch = Class.new { def execute(*) = raise("must not call") }.new
    use_case = described_class.new(container: store.container, call: ctx, get: pure_get,
                                   orchestrator: orch)

    expect(use_case.call("knowledge.doc")).to be_nil
  end
end
