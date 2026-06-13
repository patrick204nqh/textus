require "spec_helper"

RSpec.describe Textus::Maintenance::Drain do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge feeds],
      manifest: <<~YAML,
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
          - { name: feeds, kind: machine }
        entries:
          - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
          - key: feeds.catalog
            kind: produced
            path: data/feeds/catalog.json
            lane: feeds
            source: { from: derive, select: "knowledge", pluck: [title] }
      YAML
      files: {
        "data/knowledge/a.md" => "---\ntitle: Apple\n---\nhello\n",
        "templates/catalog.mustache" => "{{#entries}}{{title}}\n{{/entries}}",
      },
    )
  end

  it "queue-burns only queued jobs and does not seed new work" do
    result = store.as("human").drain

    expect(result["ok"]).to be true
    expect(result["completed"]).to eq(0)
    expect(Textus::Ports::Queue.new(root: root).ready_ids).to be_empty
  end

  it "reports not-ok when a job dead-letters" do
    queue = Textus::Ports::Queue.new(root: root)
    job = Textus::Core::Jobs::Job.new(type: "unknown", args: {}, max_attempts: 1)
    queue.enqueue(job)

    result = described_class.new(container: store.container, call: test_ctx(role: "human")).call
    expect(result["ok"]).to be false
    expect(result["failed"]).to eq(1)
  end
end
