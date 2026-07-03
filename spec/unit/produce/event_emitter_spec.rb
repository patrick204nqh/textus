require "spec_helper"

RSpec.describe Textus::Produce::EventEmitter do
  subject(:emitter) { described_class.new(event_store:, workflow_registry:) }

  let(:event_store) { instance_double(Textus::Store::EventStore) }
  let(:workflow_registry) { instance_double(Textus::Workflow::Registry) }
  let(:materialize) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize", max_attempts: 3) }

  describe "#emit" do
    before { allow(event_store).to receive(:emit) }

    it "emits one event per workflow registered for the event type" do
      allow(workflow_registry).to receive(:workflows_for).with("entry.written").and_return([materialize])

      count = emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge", payload: { "x" => 1 })

      expect(event_store).to have_received(:emit).with(
        event_type: "entry.written", workflow_type: "materialize",
        key: "knowledge.a", lane: "knowledge", payload: { "x" => 1 },
        max_attempts: 3
      )
      expect(count).to eq(1)
    end

    it "returns 0 and emits nothing when no workflow handles the event type" do
      allow(workflow_registry).to receive(:workflows_for).with("entry.written").and_return([])

      expect(emitter.emit(event_type: "entry.written", key: "knowledge.a")).to eq(0)
      expect(event_store).not_to have_received(:emit)
    end
  end
end
