module Textus
  module Surfaces
    module MCP
      # Audit cursor fell off the keep window. Client should re-boot and
      # resume from the new latest_seq.
      class CursorExpired < Textus::Error
        JSONRPC_CODE = -32_002

        def initialize(message, details: {})
          super("cursor_expired", message, details: details)
        end
      end

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
