# rubocop:disable Lint/EmptyBlock
require "spec_helper"

RSpec.describe "textus/3 hook event names" do
  let(:registry) { Textus::Hooks::Registry.new }

  it "accepts canonical textus/3 event names" do
    Textus.with_registry(registry) do
      Textus.on(:resolve_intake,    :handler_a)       { |**| { _meta: {}, body: "x" } }
      Textus.on(:transform_rows,    :reducer_a)       { |rows:, **| rows }
      Textus.on(:validate,          :checker_a)       { |**| [] }
      Textus.on(:entry_put,         :listener_a)      { |**| }
      Textus.on(:store_loaded,      :loaded_listener) { |**| }
      Textus.on(:build_completed,   :built_listener)  { |**| }
      Textus.on(:proposal_accepted, :accepted_listener) { |**| }
      Textus.on(:proposal_rejected, :rejected_listener) { |**| }
      Textus.on(:file_published,    :published_listener) { |**| }
      Textus.on(:entry_renamed,     :renamed_listener) { |**| }
      Textus.on(:entry_refreshed,   :refreshed_listener) { |**| }
      Textus.on(:entry_deleted,     :deleted_listener) { |**| }
      Textus.on(:refresh_started,   :started_listener) { |**| }
      Textus.on(:refresh_backgrounded, :backgrounded_listener) { |**| }
      Textus.on(:refresh_failed,   :failed_listener) { |**| }
    end
    canonical = %i[resolve_intake transform_rows validate entry_put entry_deleted entry_refreshed
                   entry_renamed build_completed proposal_accepted proposal_rejected
                   file_published store_loaded refresh_started refresh_failed refresh_backgrounded]
    canonical.each { |ev| expect { registry.rpc_callable(ev, :_) }.to raise_error(Textus::UsageError) }
  end

  it "rejects legacy :put with migration hint" do
    Textus.with_registry(registry) do
      expect { Textus.on(:put, :x) { |**| } }
        .to raise_error(Textus::UsageError, /:put.*renamed to.*:entry_put/i)
    end
  end

  it "rejects legacy :intake with migration hint" do
    Textus.with_registry(registry) do
      expect { Textus.on(:intake, :x) { |**| {} } }
        .to raise_error(Textus::UsageError, /:intake.*renamed to.*:resolve_intake/i)
    end
  end

  it "rejects legacy :built with migration hint" do
    Textus.with_registry(registry) do
      expect { Textus.on(:built, :x) { |**| } }
        .to raise_error(Textus::UsageError, /:built.*renamed to.*:build_completed/i)
    end
  end
end
# rubocop:enable Lint/EmptyBlock
