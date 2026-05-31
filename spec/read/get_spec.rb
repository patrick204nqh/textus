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

  def build_store_no_intake
    minimal_store(root, key: "working.doc", path: "working/doc.md")
  end

  def build_store_with_intake(ttl:, on_stale: "warn")
    intake_store(root, intake_body: intake_body, ttl: ttl, on_stale: on_stale)
  end

  def write_doc(last_fetched_at: Time.now.utc.iso8601)
    File.write(File.join(root, "zones", "working", "doc.md"), <<~MD)
      ---
      name: doc
      last_fetched_at: "#{last_fetched_at}"
      ---
      stored body
    MD
  end

  def build_use_case(store)
    container = Textus::Container.from_store(store)
    call = Textus::Call.build(role: "automation")
    described_class.new(container: container, call: call)
  end

  it "returns nil when the file does not exist on disk" do
    store = build_store_no_intake
    use_case = build_use_case(store)
    expect(use_case.call("working.doc")).to be_nil
  end

  it "annotates as fresh when no fetch policy applies" do
    store = build_store_no_intake
    write_doc
    env = build_use_case(store).call("working.doc")
    expect(env.freshness.stale).to be(false)
    expect(env.freshness.fetching).to be(false)
  end

  it "annotates as fresh when the envelope is within TTL" do
    store = build_store_with_intake(ttl: "1h", on_stale: "warn")
    write_doc(last_fetched_at: Time.now.utc.iso8601)
    env = build_use_case(store).call("working.doc")
    expect(env.freshness.stale).to be(false)
  end

  it "annotates as stale when the envelope is past TTL — but does NOT fetch" do
    store = build_store_with_intake(ttl: "1s", on_stale: "timed_sync")
    write_doc(last_fetched_at: "2020-01-01T00:00:00Z")
    env = build_use_case(store).call("working.doc")
    expect(env.freshness.stale).to be(true)
    expect(env.freshness.fetching).to be(false)
  end

  it "does not accept an orchestrator: kwarg (signal of the contract)" do
    store = build_store_no_intake
    container = Textus::Container.from_store(store)
    call = Textus::Call.build(role: "automation")
    expect do
      described_class.new(container: container, call: call, orchestrator: Object.new)
    end.to raise_error(ArgumentError, /unknown keyword: :orchestrator/)
  end
end
