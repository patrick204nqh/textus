RSpec.describe Textus::Workflow::Queue do
  subject(:queue) { described_class.new(workflow_queue, registry:, container:, call:) }

  let(:workflow_queue) { instance_double(Textus::Infra::Store::WorkflowQueue) }
  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:materialize) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize", max_attempts: 3) }
  let(:container) { instance_double(Textus::Protocol::Container) }
  let(:call) { instance_double(Textus::Value::Call) }

  describe "#enqueue" do
    before { allow(workflow_queue).to receive(:push) }

    it "emits one event per workflow registered for the event type" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([materialize])

      count = queue.enqueue(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")

      expect(workflow_queue).to have_received(:push).with(
        event_type: "entry.written", workflow_type: "materialize",
        key: "knowledge.a", lane: "knowledge", payload: nil,
        max_attempts: 3
      )
      expect(count).to eq(1)
    end

    it "returns 0 and emits nothing when no workflow handles the event type" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([])

      expect(queue.enqueue(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")).to eq(0)
      expect(workflow_queue).not_to have_received(:push)
    end
  end
end
