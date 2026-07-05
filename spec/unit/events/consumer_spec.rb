RSpec.describe Textus::Workflow::Queue do
  subject(:queue) { described_class.new(workflow_queue, registry:, container:, call:) }

  let(:workflow_queue) { instance_double(Textus::Infra::Store::WorkflowQueue) }
  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:workflow) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize") }
  let(:container) { instance_double(Textus::Protocol::Container) }
  let(:call) { instance_double(Textus::Value::Call) }
  let(:pending_row) { { id: 1, key: "knowledge.a", workflow_type: "materialize", retry_count: 0, max_attempts: 3, state: "pending" } }
  let(:terminal_row) { { id: 2, key: "knowledge.b", workflow_type: "materialize", retry_count: 3, max_attempts: 3, state: "pending" } }

  before do
    allow(registry).to receive(:for).with("materialize").and_return(workflow)
  end

  describe "#drain" do
    it "loops until pop returns nil, tallying completed and failed" do
      rows = [
        pending_row.merge(id: 1),
        pending_row.merge(id: 2, retry_count: 3, max_attempts: 3),
        nil,
      ]
      allow(workflow_queue).to receive(:pop).and_return(*rows)
      call_count = 0
      allow(Textus::Workflow::Runner).to receive(:new) do
        call_count += 1
        runner = instance_double(Textus::Workflow::Runner)
        if call_count == 1
          allow(runner).to receive(:run)
        else
          allow(runner).to receive(:run).and_raise(StandardError.new("boom"))
        end
        runner
      end
      allow(workflow_queue).to receive(:mark_processing)
      allow(workflow_queue).to receive(:complete)
      allow(workflow_queue).to receive(:fail)

      result = queue.drain

      expect(result).to eq(completed: 1, failed: 1)
    end
  end
end
