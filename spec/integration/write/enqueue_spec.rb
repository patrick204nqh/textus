require "spec_helper"

RSpec.describe Textus::Write::Enqueue do
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
  let(:queue) { Textus::Ports::Queue.new(root: root) }

  it "enqueues a registered type stamped with the caller's role" do
    store.as("automation").enqueue("materialize", { "key" => "knowledge.a" })
    id = queue.ready_ids.find { |i| i.start_with?("materialize:") }
    body = JSON.parse(File.read(File.join(Textus::Layout.queue_state(root, :ready), "#{id}.json")))
    expect(body["enqueued_by"]).to eq("automation")
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
