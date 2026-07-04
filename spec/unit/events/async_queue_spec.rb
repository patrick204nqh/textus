RSpec.describe Textus::Protocol::Async::Queue do
  subject(:queue) { described_class.new(workflow_queue) }

  let(:workflow_queue) { instance_double(Textus::Infra::Store::WorkflowQueue) }
  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:workflow) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize") }
  let(:container) { instance_double(Textus::Protocol::Container) }
  let(:call) { instance_double(Textus::Value::Call) }
  let(:pending_row) { { id: 1, key: "knowledge.a", workflow_type: "materialize", retry_count: 0, max_attempts: 3 } }

  before do
    allow(registry).to receive(:for).with("materialize").and_return(workflow)
  end

  describe "#consume_one" do
    it "returns nil when there is no pending event" do
      allow(workflow_queue).to receive(:pop).and_return(nil)

      expect(queue.consume_one(registry:, container:, call:)).to be_nil
    end

    it "runs the workflow and marks the event done on success" do
      allow(workflow_queue).to receive(:pop).and_return(pending_row)
      allow(workflow_queue).to receive(:mark_processing)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:)
                                                      .and_return(instance_double(Textus::Workflow::Runner, run: nil))
      allow(workflow_queue).to receive(:complete)

      result = queue.consume_one(registry:, container:, call:)

      expect(workflow_queue).to have_received(:mark_processing).with(1)
      expect(workflow_queue).to have_received(:complete).with(1)
      expect(result[:state]).to eq("done")
    end

    it "reschedules with backoff when the workflow raises and retries remain" do
      allow(workflow_queue).to receive(:pop).and_return(pending_row)
      allow(workflow_queue).to receive(:mark_processing)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:).and_raise(StandardError.new("boom"))
      allow(workflow_queue).to receive(:reschedule)

      result = queue.consume_one(registry:, container:, call:)

      expect(workflow_queue).to have_received(:mark_processing).with(1)
      expect(workflow_queue).to have_received(:reschedule).with(1, retry_count: 1, delay: 10, error: "boom")
      expect(result[:state]).to eq("retrying")
    end

    it "marks the event failed (dead-letters it) once max_attempts is reached" do
      exhausted_row = pending_row.merge(retry_count: 2, max_attempts: 3)
      allow(workflow_queue).to receive(:pop).and_return(exhausted_row)
      allow(workflow_queue).to receive(:mark_processing)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:).and_raise(StandardError.new("boom"))
      allow(workflow_queue).to receive(:fail)

      result = queue.consume_one(registry:, container:, call:)

      expect(workflow_queue).to have_received(:fail).with(1, retry_count: 3, error: "boom")
      expect(result[:state]).to eq("failed")
      expect(result[:error]).to eq("boom")
    end
  end
end
