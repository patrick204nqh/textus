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

    it "pushes one event per workflow registered for the event type" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([materialize])

      count = emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")

      expect(workflow_queue).to have_received(:push).with(
        event_type: "entry.written", workflow_type: "materialize",
        key: "knowledge.a", lane: "knowledge",
        max_attempts: 3
      )
      expect(count).to eq(1)
    end

    it "pushes key-matched workflows not already queued by event type" do
      doctor = instance_double(Textus::Workflow::DSL::Definition, type: "doctor", max_attempts: 3)
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([materialize])
      allow(registry).to receive(:workflows_for_key).with("knowledge.a").and_return([doctor])

      count = emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")

      expect(workflow_queue).to have_received(:push).with(
        hash_including(workflow_type: "materialize")
      )
      expect(workflow_queue).to have_received(:push).with(
        hash_including(workflow_type: "doctor")
      )
      expect(count).to eq(2)
    end

    it "does not double-queue a workflow that matches both event and key" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([materialize])
      allow(registry).to receive(:workflows_for_key).with("knowledge.a").and_return([materialize])

      count = emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")

      expect(workflow_queue).to have_received(:push).once
      expect(count).to eq(1)
    end

    it "emits nothing when no workflow matches" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([])
      allow(registry).to receive(:workflows_for_key).with("knowledge.a").and_return([])

      expect(emitter.emit(event_type: "entry.written", key: "knowledge.a", lane: "knowledge")).to eq(0)
      expect(workflow_queue).not_to have_received(:push)
    end

    it "defaults to the artifacts lane" do
      allow(registry).to receive(:workflows_for).with("entry.written").and_return([materialize])

      emitter.emit(event_type: "entry.written", key: "knowledge.a")

      expect(workflow_queue).to have_received(:push).with(
        hash_including(lane: "artifacts"),
      )
    end
  end
end
