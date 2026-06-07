# rubocop:disable Lint/EmptyBlock
require "spec_helper"

RSpec.describe "textus/3 canonical hook events" do
  let(:events) { Textus::Hooks::EventBus.new }
  let(:rpc)    { Textus::Hooks::RpcRegistry.new }

  it "accepts canonical textus/3 event names" do # rubocop:disable RSpec/ExampleLength
    rpc.register(:resolve_handler, :handler_a) { |**| { _meta: {}, body: "x" } }
    rpc.register(:transform_rows,    :reducer_a)         { |rows:, **| rows }
    rpc.register(:validate,          :checker_a)         { |**| [] }
    events.on(:entry_written, :listener_a) { |**| }
    events.on(:store_loaded,      :loaded_listener)   { |**| }
    events.on(:session_opened,    :opened_listener)   { |**| }
    events.on(:entry_produced, :built_listener) { |**| }
    events.on(:proposal_accepted, :accepted_listener) { |**| }
    events.on(:proposal_rejected, :rejected_listener) { |**| }
    events.on(:entry_published, :published_listener) { |**| }
    events.on(:entry_renamed, :renamed_listener) { |**| }
    events.on(:entry_fetched, :fetched_listener) { |**| }
    events.on(:entry_deleted, :deleted_listener) { |**| }
    events.on(:entry_fetch_started, :started_listener) { |**| }
    events.on(:entry_fetch_failed, :failed_listener) { |**| }

    # RPC events should not be accessible on EventBus
    rpc_events = %i[resolve_handler transform_rows validate]
    rpc_events.each do |ev|
      expect { events.on(ev, :_) { |**| } }.to raise_error(Textus::UsageError)
    end

    # Pubsub events should not be accessible on RpcRegistry
    pubsub_events = %i[entry_written entry_deleted entry_fetched entry_renamed entry_produced
                       proposal_accepted proposal_rejected entry_published store_loaded
                       session_opened
                       entry_fetch_started entry_fetch_failed]
    pubsub_events.each do |ev|
      expect { rpc.register(ev, :_) { |**| } }.to raise_error(Textus::UsageError)
    end
  end
end
# rubocop:enable Lint/EmptyBlock
