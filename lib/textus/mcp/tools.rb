module Textus
  module MCP
    # Thin delegator kept for name stability (ADR 0039). The dispatch table
    # and JSON schemas are now DERIVED from per-verb contracts by MCP::Catalog;
    # this module only forwards.
    module Tools
      module_function

      def call(name, session:, store:, args:)
        Catalog.call(name, session: session, store: store, args: args || {})
      end
    end
  end
end
