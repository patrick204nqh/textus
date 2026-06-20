# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Jobs::Queue do
  subject(:queue) { described_class.new(store: store) }

  let(:root) { File.join(Dir.mktmpdir, ".textus") }
  let(:store) { Textus::Port::Store.new(root: root).setup! }

  after do
    store.close
    FileUtils.rm_rf(File.dirname(root))
  end

  def job(type: "materialize", args: { "key" => "x" }, role: "automation", **rest)
    described_class::Job.new(type: type, args: args, role: role, **rest)
  end

  it "deduplicates identical ready jobs by id" do
    queue.enqueue(job)
    queue.enqueue(job)

    expect(queue.ready_ids.size).to eq(1)
  end

  it "keeps distinct args separate" do
    queue.enqueue(job(args: { "key" => "a" }))
    queue.enqueue(job(args: { "key" => "b" }))

    expect(queue.ready_ids.size).to eq(2)
  end

  it "leases one ready job and records the lease" do
    queue.enqueue(job)

    leased = queue.lease(worker_id: "w1", lease_ttl: 60)

    expect(leased.job.type).to eq("materialize")
    expect(leased.job.args).to eq({ "key" => "x" })
    expect(queue.ready_ids).to be_empty
    expect(queue.list(:leased)).to contain_exactly(leased.job.id)
  end

  it "returns nil when no job is ready" do
    expect(queue.lease(worker_id: "w1", lease_ttl: 60)).to be_nil
  end

  it "acks a leased job as done" do
    queue.enqueue(job)
    leased = queue.lease(worker_id: "w1", lease_ttl: 60)

    queue.ack(leased)

    expect(queue.list(:leased)).to be_empty
    expect(queue.list(:done)).to contain_exactly(leased.job.id)
  end

  it "requeues failed jobs and appends errors" do
    queue.enqueue(job(max_attempts: 3))
    leased = queue.lease(worker_id: "w1", lease_ttl: 60)

    expect(queue.fail(leased, error: "boom")).to eq(:requeued)
    requeued = queue.lease(worker_id: "w1", lease_ttl: 60)

    expect(requeued.job.attempts).to eq(1)
    expect(requeued.job.errors).to contain_exactly(include("attempt" => 1, "error" => "boom"))
  end

  it "dead-letters after max attempts" do
    queue.enqueue(job(max_attempts: 1))
    leased = queue.lease(worker_id: "w1", lease_ttl: 60)

    expect(queue.fail(leased, error: "boom")).to eq(:dead_lettered)

    expect(queue.ready_ids).to be_empty
    expect(queue.list(:failed)).to contain_exactly(leased.job.id)
  end

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

  it "reclaims expired leases" do
    queue.enqueue(job)
    queue.lease(worker_id: "w1", lease_ttl: -1)

    expect(queue.reclaim(now: Time.now.utc)).to eq(1)
    expect(queue.ready_ids.size).to eq(1)
  end

  it "leaves active leases alone" do
    queue.enqueue(job)
    queue.lease(worker_id: "w1", lease_ttl: 300)

    expect(queue.reclaim(now: Time.now.utc)).to eq(0)
    expect(queue.ready_ids).to be_empty
  end
end
