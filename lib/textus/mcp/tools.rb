module Textus
  module MCP
    # Thin delegator kept for name stability (ADR 0039). The dispatch table
    # and JSON schemas are now DERIVED from per-verb contracts by MCP::Catalog;
    # this module only forwards. build_registry is derived too, so the floor
    # guards (registry<->schema parity, registry<->dispatcher reconciliation)
    # keep asserting against the live contract-derived set.
    module Tools
      module_function

      def call(name, session:, store:, args:)
        Catalog.call(name, session: session, store: store, args: args || {})
      end

      # Returns a verb-name (String) -> callable Hash, derived from contracts.
      # Present so the reconciliation guards have a .build_registry.keys to read.
      # Evaluated at call time (not load time) to respect Zeitwerk lazy-loading.
      def build_registry
        Catalog.names.to_h { |n| [n, ->(s, store, a) { Catalog.call(n, session: s, store: store, args: a) }] }
      end
    end
  end
end
