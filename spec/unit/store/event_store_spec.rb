require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Protocol::Events::EventStore do
  subject(:event_store) { described_class.new(database) }

  let(:root) { Dir.mktmpdir }
  let(:database) { Textus::Infra::Database.new(root: root).setup! }

  after { FileUtils.remove_entry(root) }

  it "emits a pending event and makes it available via consume_pending" do
    event_store.emit(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})

    row = event_store.consume_pending
    expect(row[:workflow_type]).to eq("materialize")
    expect(row[:state]).to eq("pending")
  end

  it "marks an event done" do
    event_store.emit(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = event_store.consume_pending

    event_store.mark_done(event_id: row[:id])

    expect(event_store.consume_pending).to be_nil
  end

  it "marks an event failed with an error message" do
    event_store.emit(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = event_store.consume_pending

    event_store.mark_failed(event_id: row[:id], retry_count: 3, error: "boom")

    expect(event_store.consume_pending).to be_nil
  end

  it "reschedules an event into the future" do
    event_store.emit(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = event_store.consume_pending

    event_store.reschedule(event_id: row[:id], retry_count: 1, delay: 3600, error: "transient")

    expect(event_store.consume_pending).to be_nil
  end

  it "no longer responds to search_entries (moved to Store::EntryIndex)" do
    expect(event_store).not_to respond_to(:search_entries)
  end
end
