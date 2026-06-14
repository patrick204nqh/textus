require "spec_helper"

RSpec.describe Textus::Dispatch::Gate do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }
  let(:gate) { described_class.new(store.container) }

  let(:no_op_action) do
    klass = Class.new(Textus::Dispatch::Actions::Base) do
      def call(container:, call:)
        _ = container
        _ = call
        :done
      end

      def args = {}
    end
    klass.const_set(:BURN, :sync)
    klass.new
  end

  it "runs auth -> ledger -> executor and returns results array" do
    event = Textus::Dispatch::Event.new(
      name: "entry.get",
      actor: "human",
      target: "knowledge.foo",
      payload: {},
      actions: [no_op_action],
      correlation_id: "xyz",
    )

    expect(gate.fire(event)).to eq([:done])
  end

  it "raises WriteForbidden for unauthorized write action" do
    action_klass = Class.new(Textus::Dispatch::Actions::Base) do
      def initialize(key:)
        super()
        @key = key
      end

      def call(container:, call:)
        Textus::Dispatch::Actions::Put.new(key: @key, body: "x").call(container: container, call: call)
      end

      def args = { key: @key }
    end
    action_klass.const_set(:BURN, :sync)
    write_action = action_klass.new(key: "knowledge.foo")

    event = Textus::Dispatch::Event.new(
      name: "entry.put",
      actor: "agent",
      target: "knowledge.foo",
      payload: {},
      actions: [write_action],
      correlation_id: nil,
    )

    expect { gate.fire(event) }.to raise_error(Textus::WriteForbidden)
  end

  it "checks session etag when session provided" do
    session = Textus::Session.new(
      role: "human",
      cursor: nil,
      propose_lane: nil,
      contract_etag: "sha256:wrong",
    )
    event = Textus::Dispatch::Event.new(
      name: "entry.get",
      actor: "human",
      target: "knowledge.foo",
      payload: {},
      actions: [no_op_action],
      correlation_id: nil,
    )

    expect { gate.fire(event, session: session) }.to raise_error(Textus::Surfaces::MCP::ContractDrift)
  end
end
