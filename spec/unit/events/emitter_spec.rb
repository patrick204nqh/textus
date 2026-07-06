RSpec.describe Textus::Workflow::EventEmitter do
  subject(:emitter) { described_class.new(workflow_queue, registry:) }

  let(:workflow_queue) { instance_double(Textus::Infra::Store::WorkflowQueue) }
  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:materialize) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize", max_attempts: 3) }

  describe "#emit" do
    before do
      allow(workflow_queue).to receive(:push)
      allow(registry).to receive(:workflows_for_key).and_return([])
    end

    it "emits one event per workflow registered for the event type" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([materialize])

      count = emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")

      expect(workflow_queue).to have_received(:push).with(
        event_type: "entry.written", workflow_type: "materialize",
        key: "knowledge.a", lane: "knowledge",
        max_attempts: 3
      )
      expect(count).to eq(1)
    end

    it "returns 0 and emits nothing when no workflow matches" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([])
      allow(registry).to receive(:workflows_for_key).with("knowledge.a").and_return([])

      expect(emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")).to eq(0)
      expect(workflow_queue).not_to have_received(:push)
    end
  end
end
