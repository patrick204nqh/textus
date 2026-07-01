require "spec_helper"

RSpec.describe Textus::Store::Jobs::Worker do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }
  let(:queue) { Textus::Store::Jobs::Queue.new(store: store.job_store) }
  let(:worker) { described_class.for(container: store.container, queue: queue) }

  it "returns typed outcomes from run_one" do
    # Create an unregistered job type so run_one hits queue.fail path.
    job = Textus::Store::Jobs::Queue::Job.new(type: "unknown_job", args: {}, role: "automation", max_attempts: 1)
    queue.enqueue(job)
    leased = queue.lease(worker_id: "spec-worker", lease_ttl: 5)

    outcome = worker.send(:run_one, leased)

    expect(outcome).to respond_to(:kind)
    expect(outcome.kind).to(
      be(:completed)
        .or(be(:retryable_failure))
        .or(be(:dead_lettered))
        .or(be(:skipped_lock)),
    )
  end
end
