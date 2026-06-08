require "spec_helper"

RSpec.describe Textus::Maintenance::Serve do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }
    YAML
  end

  it "tick seeds + reclaims + drains the queue to empty" do
    queue = Textus::Ports::Queue.new(root: root)
    queue.enqueue(Textus::Domain::Jobs::Job.new(type: "materialize", args: { "key" => "x" },
                                                enqueued_by: "automation"))
    serve = described_class.new(container: store.container, call: test_ctx(role: "automation"))
    allow(Textus::Produce::Engine).to receive(:converge) # don't actually build

    serve.tick

    # the pre-enqueued materialize job plus the scheduler's seeded sweep all drain
    expect(queue.ready_ids).to be_empty
    expect(queue.list(:done)).not_to be_empty
  end
end
