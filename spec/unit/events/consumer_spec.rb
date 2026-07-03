require "spec_helper"

RSpec.describe Textus::Protocol::Events::Consumer do
  subject(:consumer) { described_class.new }

  let(:event_store) { instance_double(Textus::Store::EventStore) }
  let(:registry) { instance_double(Textus::Workflow::Registry) }
  let(:workflow) { instance_double(Textus::Workflow::DSL::Definition, type: "materialize") }
  let(:container) { instance_double(Textus::Store::Container) }
  let(:call) { instance_double(Textus::Value::Call) }
  let(:pending_row) { { id: 1, key: "knowledge.a", workflow_type: "materialize", retry_count: 0, max_attempts: 3, state: "pending" } }

  before do
    allow(registry).to receive(:for).with("materialize").and_return(workflow)
  end

  describe "#consume_one" do
    it "returns nil when there is no pending event" do
      allow(event_store).to receive(:consume_pending).and_return(nil)

      expect(consumer.consume_one(event_store:, registry:, container:, call:)).to be_nil
    end

    it "runs the workflow and marks the event done on success" do
      allow(event_store).to receive(:consume_pending).and_return(pending_row)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:)
                                                      .and_return(instance_double(Textus::Workflow::Runner, run: nil))
      allow(event_store).to receive(:mark_done)

      result = consumer.consume_one(event_store:, registry:, container:, call:)

      expect(event_store).to have_received(:mark_done).with(event_id: 1)
      expect(result[:state]).to eq("done")
    end

    it "reschedules with backoff when the workflow raises and retries remain" do
      allow(event_store).to receive(:consume_pending).and_return(pending_row)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:).and_raise(StandardError.new("boom"))
      allow(event_store).to receive(:reschedule)

      result = consumer.consume_one(event_store:, registry:, container:, call:)

      expect(event_store).to have_received(:reschedule).with(event_id: 1, retry_count: 1, delay: 10, error: "boom")
      expect(result[:state]).to eq("retrying")
    end

    it "marks the event failed (dead-letters it) once max_attempts is reached" do
      exhausted_row = pending_row.merge(retry_count: 2, max_attempts: 3)
      allow(event_store).to receive(:consume_pending).and_return(exhausted_row)
      allow(Textus::Workflow::Runner).to receive(:new).with(workflow, container:, call:).and_raise(StandardError.new("boom"))
      allow(event_store).to receive(:mark_failed)

      result = consumer.consume_one(event_store:, registry:, container:, call:)

      expect(event_store).to have_received(:mark_failed).with(event_id: 1, retry_count: 3, error: "boom")
      expect(result[:state]).to eq("failed")
      expect(result[:error]).to eq("boom")
    end
  end

  describe "#drain" do
    it "loops until consume_pending returns nil, tallying completed and failed" do
      rows = [
        pending_row.merge(id: 1),
        pending_row.merge(id: 2, retry_count: 2, max_attempts: 3),
        nil,
      ]
      allow(event_store).to receive(:consume_pending).and_return(*rows)
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
      allow(event_store).to receive(:mark_done)
      allow(event_store).to receive(:mark_failed)

      result = consumer.drain(event_store:, registry:, container:, call:)

      expect(result).to eq(completed: 1, failed: 1)
    end
  end
end
