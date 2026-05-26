# rubocop:disable Lint/EmptyBlock
require "spec_helper"

RSpec.describe "textus/3 canonical hook events" do
  let(:registry) { Textus::Hooks::Registry.new }

  it "accepts canonical textus/3 event names" do
    registry.on(:resolve_intake,    :handler_a)         { |**| { _meta: {}, body: "x" } }
    registry.on(:transform_rows,    :reducer_a)         { |rows:, **| rows }
    registry.on(:validate,          :checker_a)         { |**| [] }
    registry.on(:entry_put,         :listener_a)        { |**| }
    registry.on(:store_loaded,      :loaded_listener)   { |**| }
    registry.on(:build_completed,   :built_listener)    { |**| }
    registry.on(:proposal_accepted, :accepted_listener) { |**| }
    registry.on(:proposal_rejected, :rejected_listener) { |**| }
    registry.on(:file_published,    :published_listener) { |**| }
    registry.on(:entry_renamed,     :renamed_listener) { |**| }
    registry.on(:entry_refreshed,   :refreshed_listener) { |**| }
    registry.on(:entry_deleted,     :deleted_listener)  { |**| }
    registry.on(:refresh_started,   :started_listener)  { |**| }
    registry.on(:refresh_backgrounded, :backgrounded_listener) { |**| }
    registry.on(:refresh_failed, :failed_listener) { |**| }

    canonical = %i[resolve_intake transform_rows validate entry_put entry_deleted entry_refreshed
                   entry_renamed build_completed proposal_accepted proposal_rejected
                   file_published store_loaded refresh_started refresh_failed refresh_backgrounded]
    canonical.each { |ev| expect { registry.rpc_callable(ev, :_) }.to raise_error(Textus::UsageError) }
  end
end
# rubocop:enable Lint/EmptyBlock
