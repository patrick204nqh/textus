# frozen_string_literal: true

module Textus
  module Hooks
    # The single source of truth for hook event names and their required
    # kwargs. EventBus, RpcRegistry, and the Loader DSL router all read these
    # tables directly — the registries do not keep their own copies. Catalog
    # references no other constant, so it has no load-order cycle, which is
    # what removed the previous drift hazard (EventBus held a hard-coded
    # `RPC_EVENTS` list that could fall out of sync with RpcRegistry's table).
    module Catalog
      # Pub-sub events: 0..N handlers, fire-and-forget, receive `ctx:`.
      PUBSUB = {
        entry_put: %i[ctx key envelope],
        entry_deleted: %i[ctx key],
        entry_fetched: %i[ctx key envelope change],
        entry_renamed: %i[ctx key from_key to_key envelope],
        build_completed: %i[ctx key envelope sources],
        materialize_failed: %i[ctx keys error],
        proposal_accepted: %i[ctx key target_key],
        proposal_rejected: %i[ctx key target_key],
        file_published: %i[ctx key envelope source target],
        store_loaded: %i[ctx],
        session_opened: %i[ctx role cursor],
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
