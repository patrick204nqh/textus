require "spec_helper"

RSpec.describe Textus::Dispatch::Executor do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }
  let(:executor) { described_class.new(store.container) }

  let(:sync_action) do
    klass = Class.new(Textus::Dispatch::Actions::Base) do
      def call(container:, call:)
        _ = container
        _ = call
        "sync_result"
      end

      def args = {}
    end
    klass.const_set(:BURN, :sync)
    klass.new
  end

  let(:async_action) do
    klass = Class.new(Textus::Dispatch::Actions::Base) do
      def call(container:, call:)
        _ = container
        _ = call
        "async_result"
      end

      def args = { key: "test.key" }
    end
    klass.const_set(:BURN, :async)
    klass.new
  end

  it "runs sync action inline and returns result" do
    event = Textus::Dispatch::Event.new(
      name: "test.event",
      actor: "human",
      target: "k.foo",
      payload: {},
      actions: [sync_action],
      correlation_id: nil,
    )

    expect(executor.run(event)).to eq(["sync_result"])
  end

  it "enqueues async action and returns nil" do
    event = Textus::Dispatch::Event.new(
      name: "test.event",
      actor: "human",
      target: "k.foo",
      payload: {},
      actions: [async_action],
      correlation_id: nil,
    )

    results = executor.run(event)
    expect(results).to eq([nil])

    queue = Textus::Ports::Queue.new(root: root)
    expect(queue.ready_ids).not_to be_empty
  end
end
