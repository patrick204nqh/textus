require "spec_helper"

RSpec.describe Textus::Action::Jobs do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
    YAML
  end
  let(:queue) { Textus::Ports::Queue.new(root: root) }

  it "lists ready job ids" do
    queue.enqueue(Textus::Ports::Queue::Job.new(type: "materialize", args: { "key" => "x" }))
    result = store.as("human").jobs(state: "ready")
    expect(result["jobs"]).to include(a_string_starting_with("materialize:"))
  end

  it "retries a failed job back to ready" do
    job = Textus::Ports::Queue::Job.new(type: "materialize", args: { "key" => "x" }, max_attempts: 1)
    queue.enqueue(job)
    leased = queue.lease(worker_id: "w", lease_ttl: 60)
    queue.fail(leased, error: "boom") # -> failed/
    store.as("human").jobs(state: "failed", action: "retry", job_id: job.id)
    expect(queue.ready_ids).to include(job.id)
  end
end
