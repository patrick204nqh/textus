# rubocop:disable Lint/EmptyBlock
require "spec_helper"

RSpec.describe "textus/3 canonical hook events" do
  let(:events) { Textus::Hooks::EventBus.new }
  let(:rpc)    { Textus::Hooks::RpcRegistry.new }

  it "accepts canonical textus/3 event names" do
    rpc.register(:resolve_intake,    :handler_a)         { |**| { _meta: {}, body: "x" } }
    rpc.register(:transform_rows,    :reducer_a)         { |rows:, **| rows }
    rpc.register(:validate,          :checker_a)         { |**| [] }
    events.on(:entry_put,         :listener_a)        { |**| }
    events.on(:store_loaded,      :loaded_listener)   { |**| }
    events.on(:build_completed,   :built_listener)    { |**| }
    events.on(:proposal_accepted, :accepted_listener) { |**| }
    events.on(:proposal_rejected, :rejected_listener) { |**| }
    events.on(:file_published,    :published_listener) { |**| }
    events.on(:entry_renamed,     :renamed_listener) { |**| }
    events.on(:entry_fetched, :fetched_listener) { |**| }
    events.on(:entry_deleted, :deleted_listener) { |**| }
    events.on(:fetch_started, :started_listener) { |**| }
    events.on(:fetch_backgrounded, :backgrounded_listener) { |**| }
    events.on(:fetch_failed, :failed_listener) { |**| }

    # RPC events should not be accessible on EventBus
    rpc_events = %i[resolve_intake transform_rows validate]
    rpc_events.each do |ev|
      expect { events.on(ev, :_) { |**| } }.to raise_error(Textus::UsageError)
    end

    # Pubsub events should not be accessible on RpcRegistry
    pubsub_events = %i[entry_put entry_deleted entry_fetched entry_renamed build_completed
                       proposal_accepted proposal_rejected file_published store_loaded
                       fetch_started fetch_failed fetch_backgrounded]
    pubsub_events.each do |ev|
      expect { rpc.register(ev, :_) { |**| } }.to raise_error(Textus::UsageError)
    end
  end
end
# rubocop:enable Lint/EmptyBlock
