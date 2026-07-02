require "spec_helper"

RSpec.describe "jobs_list / jobs_retry / jobs_purge use cases" do
  include_context "textus_store_fixture"

  let(:manifest_yaml) do
    <<~YAML
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
  end
  let(:store) { Textus::Store.new(root) }
  let(:queue) { Textus::Store::Jobs::Queue.new(store: store.job_store) }

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  it "jobs_list returns queued job ids for a state without mutating anything" do
    store.enqueue(type: "materialize", args: { "key" => "knowledge.note" })
    result = store.jobs_list(state: "ready")
    expect(result["jobs"]).to be_an(Array)
    expect(result["jobs"].size).to eq(1)
  end

  it "jobs_retry re-queues a dead-lettered job by id" do
    job = Textus::Store::Jobs::Queue::Job.new(
      type: "materialize", args: { "key" => "knowledge.note" }, role: "automation", max_attempts: 1,
    )
    queue.enqueue(job)
    leased = queue.lease(worker_id: "spec-worker", lease_ttl: 5)
    queue.fail(leased, error: "boom") # attempts (1) >= max_attempts (1): dead-lettered
    expect(store.jobs_list(state: "failed")["jobs"]).to eq([job.id])

    result = store.jobs_retry(job_id: job.id)

    expect(result["ok"]).to be(true)
    expect(store.jobs_list(state: "ready")["jobs"]).to eq([job.id])
    expect(store.jobs_list(state: "failed")["jobs"]).to eq([])
  end

  it "jobs_purge removes every job in a state" do
    store.enqueue(type: "materialize", args: { "key" => "knowledge.note" })
    result = store.jobs_purge(state: "ready")
    expect(result["ok"]).to be(true)
    expect(store.jobs_list(state: "ready")["jobs"]).to eq([])
  end
end
