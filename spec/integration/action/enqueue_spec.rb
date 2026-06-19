require "spec_helper"

RSpec.describe Textus::Action::Enqueue do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
    YAML
  end
  let(:store_port) { Textus::Ports::Store.new(root: root).setup! }
  let(:queue) { Textus::Jobs::Queue.new(store: store_port) }

  after { store_port.close }

  it "enqueues a registered type stamped with the caller's role" do
    store.as("automation").enqueue("materialize", { "key" => "knowledge.a" })
    id = queue.ready_ids.find { |i| i.start_with?("materialize:") }
    expect(id).not_to be_nil
    leased = queue.lease(worker_id: "test", lease_ttl: 60)
    expect(leased.job.role).to eq("automation")
  end

  it "rejects an unregistered type (closed allow-list)" do
    expect { store.as("automation").enqueue("rm-rf", { "path" => "/" }) }
      .to raise_error(Textus::UsageError, /unregistered job type/)
  end

  it "rejects a caller who does not hold the type's required role" do
    expect { store.as("agent").enqueue("sweep", {}) }
      .to raise_error(Textus::Error, /not authorized/)
  end

  it "allows the required-role caller to enqueue a gated type" do
    store.as("automation").enqueue("sweep", {})
    expect(queue.ready_ids).to include(a_string_starting_with("sweep:"))
  end
end
