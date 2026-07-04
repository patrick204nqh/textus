RSpec.describe Textus::Protocol::Events::Emitter do
  subject(:emitter) { described_class.new(workflow_queue:, workflow_registry:) }

  let(:workflow_queue) { instance_double(Textus::Infra::Store::WorkflowQueue) }
  let(:workflow_registry) { instance_double(Textus::Workflow::Registry) }
  let(:materialize) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize", max_attempts: 3) }

  describe "#emit" do
    before { allow(workflow_queue).to receive(:push) }

    it "emits one event per workflow registered for the event type" do
      allow(workflow_registry).to receive(:workflows_for).with("entry.written").and_return([materialize])

      count = emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge", payload: { "x" => 1 })

      expect(workflow_queue).to have_received(:push).with(
        event_type: "entry.written", workflow_type: "materialize",
        key: "knowledge.a", lane: "knowledge", payload: { "x" => 1 },
        max_attempts: 3
      )
      expect(count).to eq(1)
    end

    it "returns 0 and emits nothing when no workflow handles the event type" do
      allow(workflow_registry).to receive(:workflows_for).with("entry.written").and_return([])

      expect(emitter.emit(event_type: "entry.written", key: "knowledge.a")).to eq(0)
      expect(workflow_queue).not_to have_received(:push)
    end
  end
end
