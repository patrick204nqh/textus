module Textus
  module Surfaces
    module MCP
      # Protocol routing for the MCP JSON-RPC server. Mixed into Server so all
      # handle_* and emit_* methods are in scope without exposing them publicly.
      module Routing
        TOOL_METHODS     = %w[initialize tools/list tools/call].freeze
        RESOURCE_METHODS = %w[resources/list resources/read].freeze

        def dispatch(msg)
          rid    = msg["id"]
          params = msg["params"] || {}
          route(msg["method"], rid, params)
        end

        private

        def route(method, rid, params)
          return route_tool(method, rid, params)     if TOOL_METHODS.include?(method)
          return route_resource(method, rid, params) if RESOURCE_METHODS.include?(method)

          route_protocol(method, rid)
        end

        def route_tool(method, rid, params)
          case method
          when "initialize" then handle_initialize(rid, params)
          when "tools/list" then handle_tools_list(rid)
          when "tools/call" then handle_tools_call(rid, params)
          end
        end

        def route_resource(method, rid, params)
          case method
          when "resources/list" then handle_resources_list(rid)
          when "resources/read" then handle_resources_read(rid, params)
          end
        end

        def route_protocol(method, rid)
          case method
          when "ping"                      then emit_result(rid, {})
          when "shutdown"                  then emit_result(rid, nil)
          when "notifications/initialized" then nil
          else emit_error(rid, -32_601, "method not found: #{method}")
          end
        end
      end
    end
  end
end
