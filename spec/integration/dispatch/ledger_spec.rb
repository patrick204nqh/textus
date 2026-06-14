require "spec_helper"

RSpec.describe Textus::Dispatch::Ledger do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }
  let(:ledger) { described_class.new(store.container) }

  it "records an event to the audit log before yielding" do
    event = Textus::Dispatch::Event.new(
      name: "entry.put",
      actor: "human",
      target: "knowledge.foo",
      payload: {},
      actions: [],
      correlation_id: "test-123",
    )

    recorded_before = false
    ledger.record(event) { recorded_before = true }
    expect(recorded_before).to be(true)

    log_line = File.readlines(Textus::Layout.audit_log(root)).last
    row = JSON.parse(log_line)
    expect(row["verb"]).to eq("entry.put")
    expect(row["role"]).to eq("human")
    expect(row.dig("extras", "correlation_id")).to eq("test-123")
  end

  it "yields and returns block result" do
    event = Textus::Dispatch::Event.new(
      name: "entry.get",
      actor: "human",
      target: "knowledge.foo",
      payload: {},
      actions: [],
      correlation_id: nil,
    )

    result = ledger.record(event) { :the_result }
    expect(result).to eq(:the_result)
  end
end
