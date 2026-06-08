require "spec_helper"

RSpec.describe Textus::Ports::Queue do
  subject(:queue) { described_class.new(root: root) }

  include_context "textus_store_fixture"

  before { FileUtils.mkdir_p(root) }

  def job(type: "materialize", args: { "key" => "x" }, **rest)
    Textus::Domain::Jobs::Job.new(type: type, args: args, **rest)
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
end
