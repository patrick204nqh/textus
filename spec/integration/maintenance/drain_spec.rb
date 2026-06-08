require "spec_helper"

RSpec.describe Textus::Maintenance::Drain do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root, zones: %w[knowledge],
            manifest: <<~YAML,
              version: textus/3
              zones:
                - { name: knowledge, kind: canon }
              entries:
                - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf }
            YAML
            files: { "zones/knowledge/a.md" => "---\n---\nx\n" }
    )
  end

  it "seeds the convergence set, drains it, and reports ok with an empty queue" do
    result = store.as("human").drain
    expect(result["ok"]).to be true
    expect(Textus::Ports::Queue.new(root: root).ready_ids).to be_empty
  end

  it "reports not-ok when a job dead-letters" do
    failing = instance_double(
      Textus::Maintenance::Worker,
      drain: Textus::Maintenance::Worker::Summary.new(completed: 0, failed: 1),
    )
    allow(Textus::Maintenance::Worker).to receive(:new).and_return(failing)

    result = described_class.new(container: store.container, call: test_ctx(role: "human")).call
    expect(result["ok"]).to be false
  end
end
