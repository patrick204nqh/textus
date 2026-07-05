RSpec.describe Textus::Workflow::Queue do
  subject(:queue) { described_class.new(workflow_queue, registry:, container:, call:) }

  let(:workflow_queue) { instance_double(Textus::Infra::Store::WorkflowQueue) }
  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:container) { instance_double(Textus::Protocol::Container) }
  let(:call) { instance_double(Textus::Value::Call) }
  let(:workflow) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize") }

  let(:pending_row) { { id: 1, key: "knowledge.a", workflow_type: "materialize", retry_count: 0, max_attempts: 3 } }
  let(:terminal_row) { { id: 2, key: "knowledge.b", workflow_type: "materialize", retry_count: 3, max_attempts: 3 } }

  before do
    allow(registry).to receive(:for).with("materialize").and_return(workflow)
  end

  describe "#drain" do
    it "loops until pop returns nil, tallying completed and failed" do
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

      rows = [pending_row, terminal_row, nil]
      allow(workflow_queue).to receive(:pop).and_return(*rows)
      allow(workflow_queue).to receive(:mark_processing)
      allow(workflow_queue).to receive(:complete)
      allow(workflow_queue).to receive(:fail)

      result = queue.drain

      expect(result).to eq(completed: 1, failed: 1)
    end
  end

  describe "#consume_one" do
    it "returns nil when there is no pending event" do
      allow(workflow_queue).to receive(:pop).and_return(nil)

      expect(queue.consume_one).to be_nil
    end

    it "runs and returns the result state" do
      allow(Textus::Workflow::Runner).to receive(:new).and_return(
        instance_double(Textus::Workflow::Runner, run: nil),
      )
      allow(workflow_queue).to receive(:pop).and_return(pending_row)
      allow(workflow_queue).to receive(:mark_processing)
      allow(workflow_queue).to receive(:complete)

      result = queue.consume_one

      expect(result[:state]).to eq("done")
    end
  end
end
