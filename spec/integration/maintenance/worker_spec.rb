require "spec_helper"

RSpec.describe Textus::Maintenance::Worker do
  subject(:worker) do
    described_class.new(queue: queue, registry: registry, container: container, lease_ttl: 60)
  end

  include_context "textus_store_fixture"

  before { FileUtils.mkdir_p(root) }

  let(:queue) { Textus::Ports::Queue.new(root: root) }
  let(:registry) { Textus::Domain::Jobs::Registry.new }
  let(:container) { Object.new }

  def enqueue(type:, args: {}, max_attempts: 3)
    queue.enqueue(Textus::Domain::Jobs::Job.new(type: type, args: args, max_attempts: max_attempts))
  end

  it "runs each ready job's handler and acks it" do
    ran = []
    registry.register("ok", handler: ->(job:, **) { ran << job.args["n"] })
    enqueue(type: "ok", args: { "n" => "1" })
    enqueue(type: "ok", args: { "n" => "2" })

    summary = worker.drain

    expect(ran).to contain_exactly("1", "2")
    expect(summary.completed).to eq(2)
    expect(queue.ready_ids).to be_empty
  end

  it "requeues then dead-letters a job whose handler keeps raising" do
    registry.register("boom", handler: ->(**) { raise "nope" }, max_attempts: 2)
    enqueue(type: "boom", max_attempts: 2)

    summary = worker.drain

    expect(summary.failed).to eq(1)
    expect(Dir.children(Textus::Layout.queue_state(root, :failed)).size).to eq(1)
  end

  it "passes the container through to the handler" do
    seen = nil
    registry.register("cap", handler: ->(container:, **) { seen = container })
    enqueue(type: "cap")
    worker.drain
    expect(seen).to equal(container)
  end
end
