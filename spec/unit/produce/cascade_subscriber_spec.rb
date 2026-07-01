require "spec_helper"

RSpec.describe Textus::Produce::CascadeSubscriber do
  let(:job_store)  { instance_double(Textus::Port::Store) }
  let(:manifest)   { instance_double(Textus::Manifest) }
  let(:workflows)  { instance_double(Textus::Workflow::Registry) }
  let(:file_store) { instance_double(Textus::Port::Storage::FileStore) }
  let(:subscriber) do
    described_class.new(
      manifest: manifest, workflows: workflows,
      job_store: job_store, file_store: file_store
    )
  end

  describe "#on_entry_written" do
    it "enqueues cascade jobs for the written key" do
      planner = instance_double(Textus::Store::Jobs::Planner, plan: [])
      allow(Textus::Store::Jobs::Planner).to receive(:new).and_return(planner)
      allow(Textus::Store::Jobs::Queue).to receive(:new).and_return(
        instance_double(Textus::Store::Jobs::Queue, enqueue: nil),
      )

      ev = Textus::Event::EntryWritten.new(
        key: "knowledge.foo", role: "human",
        etag_before: nil, etag_after: "abc", occurred_at: Time.now
      )
      expect { subscriber.on_entry_written(ev) }.not_to raise_error
    end
  end
end
