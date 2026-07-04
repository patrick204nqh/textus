require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Infra::Store::WorkflowQueue do
  subject(:queue) { described_class.new(database.connection) }

  let(:root) { Dir.mktmpdir }
  let(:layout) { Textus::Protocol::Layout.new(root) }
  let(:database) { Textus::Infra::Database.new(layout:).setup! }

  after { FileUtils.remove_entry(root) }

  it "pushes a pending event and pops it" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})

    row = queue.pop
    expect(row[:workflow_type]).to eq("materialize")
  end

  it "marks an event done" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = queue.pop

    queue.complete(row[:id])

    expect(queue.pop).to be_nil
  end

  it "marks an event failed with an error message" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = queue.pop

    queue.fail(row[:id], retry_count: 3, error: "boom")

    expect(queue.pop).to be_nil
  end

  it "reschedules an event into the future" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = queue.pop

    queue.reschedule(row[:id], retry_count: 1, delay: 3600, error: "transient")

    expect(queue.pop).to be_nil
  end

  describe "#pending?" do
    it "returns true when a pending event exists for the given event_type and key" do
      queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge")

      expect(queue.pending?(event_type: "entry.written", key: "knowledge.a")).to be true
    end

    it "returns true when a processing event exists for the given event_type and key" do
      queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge")
      row = queue.pop
      queue.mark_processing(row[:id])

      expect(queue.pending?(event_type: "entry.written", key: "knowledge.a")).to be true
    end

    it "returns false when the event is done" do
      queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge")
      row = queue.pop
      queue.complete(row[:id])

      expect(queue.pending?(event_type: "entry.written", key: "knowledge.a")).to be false
    end

    it "returns false when the event is failed" do
      queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge")
      row = queue.pop
      queue.fail(row[:id], retry_count: 3, error: "boom")

      expect(queue.pending?(event_type: "entry.written", key: "knowledge.a")).to be false
    end

    it "returns false when no event exists for the key" do
      expect(queue.pending?(event_type: "entry.written", key: "knowledge.b")).to be false
    end

    it "distinguishes by event_type" do
      queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge")

      expect(queue.pending?(event_type: "entry.deleted", key: "knowledge.a")).to be false
    end
  end

  describe "#mark_processing" do
    it "moves event from pending to processing so pop no longer returns it" do
      queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge")
      row = queue.pop

      queue.mark_processing(row[:id])

      expect(queue.pop).to be_nil
    end
  end
end
