require "spec_helper"

RSpec.describe Textus::Ports::JobStore do
  subject(:queue) { described_class.new(root: root) }

  include_context "textus_store_fixture"

  before { FileUtils.mkdir_p(root) }

  def job(type: "materialize", args: { "key" => "x" }, **rest)
    Textus::Ports::JobStore::Job.new(type: type, args: args, **rest)
  end

  describe "#enqueue" do
    it "persists a ready job and lists its id" do
      queue.enqueue(job)
      expect(queue.ready_ids).to contain_exactly(job.id)
    end

    it "is a no-op when an identical job is already ready (dedup)" do
      queue.enqueue(job)
      queue.enqueue(job)
      expect(queue.ready_ids.size).to eq(1)
    end

    it "keeps distinct jobs separate" do
      queue.enqueue(job(args: { "key" => "a" }))
      queue.enqueue(job(args: { "key" => "b" }))
      expect(queue.ready_ids.size).to eq(2)
    end
  end

  describe "#lease / #ack / #fail" do
    it "moves a ready job to leased and returns it" do
      queue.enqueue(job)
      leased = queue.lease(worker_id: "w1", lease_ttl: 60)
      expect(leased.job.type).to eq("materialize")
      expect(queue.ready_ids).to be_empty
    end

    it "returns nil when nothing is ready" do
      expect(queue.lease(worker_id: "w1", lease_ttl: 60)).to be_nil
    end

    it "ack removes the leased job and records it done" do
      queue.enqueue(job)
      leased = queue.lease(worker_id: "w1", lease_ttl: 60)
      queue.ack(leased)
      expect(Dir.children(Textus::Layout.queue_state(root, :leased))).to be_empty
      expect(Dir.children(Textus::Layout.queue_state(root, :done)).size).to eq(1)
    end

    it "fail requeues to ready with an incremented attempt count" do
      queue.enqueue(job(max_attempts: 3))
      leased = queue.lease(worker_id: "w1", lease_ttl: 60)
      queue.fail(leased, error: "boom")
      expect(queue.ready_ids.size).to eq(1)
      requeued = queue.lease(worker_id: "w1", lease_ttl: 60)
      expect(requeued.job.attempts).to eq(1)
      expect(requeued.job.last_error).to eq("boom")
    end

    it "fail dead-letters once attempts reach max_attempts" do
      queue.enqueue(job(max_attempts: 1))
      leased = queue.lease(worker_id: "w1", lease_ttl: 60)
      queue.fail(leased, error: "boom")
      expect(queue.ready_ids).to be_empty
      expect(Dir.children(Textus::Layout.queue_state(root, :failed)).size).to eq(1)
    end
  end

  describe "concurrency + reclaim" do
    it "lets exactly one of two threads claim a single job" do
      queue.enqueue(job)
      claims = []
      mutex = Mutex.new
      threads = 2.times.map do |i|
        Thread.new do
          leased = queue.lease(worker_id: "w#{i}", lease_ttl: 60)
          mutex.synchronize { claims << leased } if leased
        end
      end
      threads.each(&:join)
      expect(claims.size).to eq(1)
    end

    it "reclaim returns an expired leased job to ready" do
      queue.enqueue(job)
      queue.lease(worker_id: "w1", lease_ttl: -1) # already expired
      reclaimed = queue.reclaim(now: Time.now.utc)
      expect(reclaimed).to eq(1)
      expect(queue.ready_ids.size).to eq(1)
    end

    it "reclaim leaves a still-valid lease alone" do
      queue.enqueue(job)
      queue.lease(worker_id: "w1", lease_ttl: 300)
      expect(queue.reclaim(now: Time.now.utc)).to eq(0)
      expect(queue.ready_ids).to be_empty
    end
  end
end
