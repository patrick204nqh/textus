RSpec.describe Textus::Protocol::Async::Queue do
  subject(:queue) { described_class.new(event_store) }

  let(:event_store) { instance_double(Textus::Infra::Store::EventStore) }
  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:workflow) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize") }
  let(:container) { instance_double(Textus::Protocol::Container) }
  let(:call) { instance_double(Textus::Value::Call) }
  let(:pending_row) { { id: 1, key: "knowledge.a", workflow_type: "materialize", retry_count: 0, max_attempts: 3, state: "pending" } }

  before do
    allow(registry).to receive(:for).with("materialize").and_return(workflow)
  end

  describe "#consume_one" do
    it "returns nil when there is no pending event" do
      allow(event_store).to receive(:consume_pending).and_return(nil)

      expect(queue.consume_one(registry:, container:, call:)).to be_nil
    end

    it "runs the workflow and marks the event done on success" do
      allow(event_store).to receive(:consume_pending).and_return(pending_row)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:)
                                                      .and_return(instance_double(Textus::Workflow::Runner, run: nil))
      allow(event_store).to receive(:mark_done)

      result = queue.consume_one(registry:, container:, call:)

      expect(event_store).to have_received(:mark_done).with(event_id: 1)
      expect(result[:state]).to eq("done")
    end

    it "reschedules with backoff when the workflow raises and retries remain" do
      allow(event_store).to receive(:consume_pending).and_return(pending_row)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:).and_raise(StandardError.new("boom"))
      allow(event_store).to receive(:reschedule)

      result = queue.consume_one(registry:, container:, call:)

      expect(event_store).to have_received(:reschedule).with(event_id: 1, retry_count: 1, delay: 10, error: "boom")
      expect(result[:state]).to eq("retrying")
    end

    it "marks the event failed (dead-letters it) once max_attempts is reached" do
      exhausted_row = pending_row.merge(retry_count: 2, max_attempts: 3)
      allow(event_store).to receive(:consume_pending).and_return(exhausted_row)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:).and_raise(StandardError.new("boom"))
      allow(event_store).to receive(:mark_failed)

      result = queue.consume_one(registry:, container:, call:)

      expect(event_store).to have_received(:mark_failed).with(event_id: 1, retry_count: 3, error: "boom")
      expect(result[:state]).to eq("failed")
      expect(result[:error]).to eq("boom")
    end
  end
end
