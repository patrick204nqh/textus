require "spec_helper"

RSpec.describe Textus::Maintenance::Watch do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: data/knowledge/a.md, lane: knowledge, kind: leaf }
    YAML
  end

  it "tick reclaims + drains the queue to empty" do
    queue = Textus::Ports::Queue.new(root: root)
    queue.enqueue(Textus::Core::Jobs::Job.new(type: "materialize", args: { "key" => "x" },
                                              enqueued_by: "automation"))
    watch = described_class.new(container: store.container, call: test_ctx(role: "automation"))
    allow(Textus::Produce::Engine).to receive(:converge)

    watch.tick

    expect(queue.ready_ids).to be_empty
    expect(queue.list(:done)).not_to be_empty
  end

  it "acquires watcher lock while running and releases it on exit" do
    watch = described_class.new(container: store.container, call: test_ctx(role: "automation"))

    runner = Thread.new do
      watch.run(poll: 0.01)
    rescue StandardError
      nil
    end

    sleep 0.03
    expect(Textus::Ports::WatcherLock.running?(root)).to be(true)

    runner.kill
    runner.join
    sleep 0.01

    expect(Textus::Ports::WatcherLock.running?(root)).to be(false)
  end

  it "routes scheduler ticks through dispatch gate with scheduled audit events" do
    watch = described_class.new(container: store.container, call: test_ctx(role: "automation"))

    watch.tick

    rows = File.readlines(Textus::Layout.audit_log(root)).map { |line| JSON.parse(line) }
    events = rows.map { |row| row["verb"] }
    expect(events).to include("scheduled.retention")
  end
end
