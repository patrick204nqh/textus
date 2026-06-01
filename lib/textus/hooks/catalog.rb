# frozen_string_literal: true

module Textus
  module Hooks
    # The single source of truth for hook event names and their required
    # kwargs. `EventBus::EVENTS` and `RpcRegistry::EVENTS` alias these tables,
    # and the cross-guards (EventBus rejects RPC events, RpcRegistry rejects
    # pubsub events) and the Loader DSL router all derive from them. Catalog
    # references no other constant, so it has no load-order cycle — which is
    # what lets both registries share one table instead of each keeping its
    # own copy (the drift hazard that motivated this module).
    module Catalog
      # Pub-sub events: 0..N handlers, fire-and-forget, receive `ctx:`.
      PUBSUB = {
        entry_put: %i[ctx key envelope],
        entry_deleted: %i[ctx key],
        entry_fetched: %i[ctx key envelope change],
        entry_renamed: %i[ctx key from_key to_key envelope],
        build_completed: %i[ctx key envelope sources],
        proposal_accepted: %i[ctx key target_key],
        proposal_rejected: %i[ctx key target_key],
        file_published: %i[ctx key envelope source target],
        store_loaded: %i[ctx],
        fetch_started: %i[ctx key mode],
        fetch_failed: %i[ctx key error_class error_message],
        fetch_backgrounded: %i[ctx key started_at budget_ms],
      }.freeze

      # RPC events: single handler, return value matters, receive `caps:`.
      RPC = {
        resolve_intake: %i[caps config args],
        transform_rows: %i[caps rows config],
        validate: %i[caps],
      }.freeze
    end
  end
end
