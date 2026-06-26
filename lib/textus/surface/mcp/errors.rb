module Textus
  module Surface
    module MCP
      # Tool execution failed (validation, authorization, IO). Wraps an
      # underlying Textus::Error or generic StandardError.
      class ToolError < Textus::Error
        JSONRPC_CODE = -32_000

        def initialize(message, details: {})
          super("tool_error", message, details: details)
        end
      end
    end
  end
end
