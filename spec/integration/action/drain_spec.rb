require "spec_helper"

RSpec.describe Textus::Action::Drain do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge feeds],
      manifest: <<~YAML,
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
          - { name: feeds, kind: machine }
        entries:
          - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
          - key: feeds.catalog
            kind: produced
            path: feeds/catalog.json
            lane: feeds
            source: { from: external, command: "make", sources: [] }
      YAML
      files: {
        "data/knowledge/a.md" => "---\ntitle: Apple\n---\nhello\n",
        "templates/catalog.erb" => "<% Array(entries).each do |e| %><%= e[\"title\"] %>\n<% end -%>",
      },
    )
  end

  it "seeds producible jobs then drains the queue to empty" do
    result = store.as("human").drain

    expect(result["ok"]).to be true
    expect(result["completed"]).to be >= 0
    store_port = Textus::Port::Store.new(root: root).setup!
    expect(Textus::Store::Jobs::Queue.new(store: store_port).ready_ids).to be_empty
    store_port.close
  end

  it "reports not-ok when a job dead-letters" do
    store_port = Textus::Port::Store.new(root: root).setup!
    queue = Textus::Store::Jobs::Queue.new(store: store_port)
    job = Textus::Store::Jobs::Queue::Job.new(type: "unknown", args: {}, role: "human", max_attempts: 1)
    queue.enqueue(job)
    store_port.close

    result = described_class.new.call(container: store.container, call: test_ctx(role: "human"))
    expect(result["ok"]).to be false
    expect(result["failed"]).to eq(1)
  end
end
