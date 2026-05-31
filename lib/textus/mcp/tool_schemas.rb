module Textus
  module MCP
    # Kept for name stability (ADR 0039). The JSON schemas are DERIVED from
    # per-verb contracts; this delegates to MCP::Catalog. The hand-written
    # array is gone — a kwarg rename now updates the schema automatically (and
    # the signature guard fails if the contract lags the use-case).
    module ToolSchemas
      module_function

      def all
        Catalog.tool_schemas
      end
    end
  end
end
