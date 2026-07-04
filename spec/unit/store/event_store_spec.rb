require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Infra::Store::WorkflowQueue do
  subject(:queue) { described_class.new(database.connection) }

  let(:root) { Dir.mktmpdir }
  let(:layout) { Textus::Protocol::Layout.new(root) }
  let(:database) { Textus::Infra::Database.new(layout:).setup! }

  after { FileUtils.remove_entry(root) }

  it "pushes a pending event and pops it" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})

    row = queue.pop
    expect(row[:workflow_type]).to eq("materialize")
  end

  it "marks an event done" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = queue.pop

    queue.complete(row[:id])

    expect(queue.pop).to be_nil
  end

  it "marks an event failed with an error message" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = queue.pop

    queue.fail(row[:id], retry_count: 3, error: "boom")

    expect(queue.pop).to be_nil
  end

  it "reschedules an event into the future" do
    queue.push(event_type: "entry.written", workflow_type: "materialize", key: "knowledge.a", lane: "knowledge", payload: {})
    row = queue.pop

    queue.reschedule(row[:id], retry_count: 1, delay: 3600, error: "transient")

    expect(queue.pop).to be_nil
  end
end
