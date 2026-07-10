module Textus
  module Surface
    module MCP
      module Catalog
        module_function

        def specs
          Textus::Protocol::ActionRegistry.registered.select(&:mcp?)
        end

        def build_tools(mcp_server)
          specs.map do |spec|
            schema = spec.input_schema
            schema = schema.reject { |k, v| k == :required && Array(v).empty? }
            ::MCP::Tool.define(
              name: spec.action.to_s,
              description: spec.summary,
              input_schema: schema,
            ) do |server_context:, **args|
              mcp_server.dispatch(spec.action, args, server_context)
            end
          end
        end

        def names
          specs.map(&:action).map(&:to_s)
        end

        def read_actions
          Textus::Protocol::ActionRegistry.registered
                                        .select { |s| s.read? && s.mcp? }
                                        .map { |s| s.action.to_s }
        end

        def write_actions
          Textus::Protocol::ActionRegistry.registered
                                        .select { |s| s.write? && s.mcp? }
                                        .map { |s| s.action.to_s }
        end

      end
    end
  end
end
