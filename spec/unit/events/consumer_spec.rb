RSpec.describe Textus::Workflow::Consumer do
  subject(:consumer) { described_class.new(registry:, container:, call:) }

  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:container) { instance_double(Textus::Protocol::Container) }
  let(:call) { instance_double(Textus::Value::Call) }
  let(:workflow) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize") }
  let(:workflow_queue) { instance_double(Textus::Infra::Store::WorkflowQueue) }
  let(:pending_row) { { id: 1, key: "knowledge.a", workflow_type: "materialize", retry_count: 0, max_attempts: 3 } }
  let(:terminal_row) { { id: 2, key: "knowledge.b", workflow_type: "materialize", retry_count: 3, max_attempts: 3 } }

  before do
    allow(registry).to receive(:for).with("materialize").and_return(workflow)
  end

  describe "#consume" do
    it "runs the workflow and marks complete on success" do
      allow(workflow_queue).to receive(:mark_processing)
      allow(workflow_queue).to receive(:complete)
      allow(Textus::Workflow::Runner).to receive(:new).and_return(
        instance_double(Textus::Workflow::Runner, run: nil),
      )

      result = consumer.consume(pending_row, workflow_queue)

      expect(workflow_queue).to have_received(:mark_processing).with(1)
      expect(workflow_queue).to have_received(:complete).with(1)
      expect(result[:state]).to eq("done")
    end

    it "fails when max_attempts reached" do
      allow(workflow_queue).to receive(:mark_processing)
      allow(workflow_queue).to receive(:fail)
      allow(Textus::Workflow::Runner).to receive(:new).and_raise(StandardError.new("boom"))

      result = consumer.consume(terminal_row, workflow_queue)

      expect(workflow_queue).to have_received(:fail).with(2, retry_count: 4, error: "boom")
      expect(result[:state]).to eq("failed")
    end

    it "reschedules with backoff when retries remain" do
      allow(workflow_queue).to receive(:mark_processing)
      allow(workflow_queue).to receive(:reschedule)
      allow(Textus::Workflow::Runner).to receive(:new).and_raise(StandardError.new("boom"))

      result = consumer.consume(pending_row, workflow_queue)

      expect(workflow_queue).to have_received(:reschedule).with(1, retry_count: 1, delay: 10, error: "boom")
      expect(result[:state]).to eq("retrying")
    end
  end
end
