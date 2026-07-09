module Textus
  module Surface
    module MCP
      module Catalog
        MCP_ADAPTER = Textus::Surface::MCP::Adapters::McpAdapter.new

        module_function

        def specs
          Textus::Protocol::VerbRegistry.registered.select(&:mcp?)
        end

        def build_tools(mcp_server)
          specs.map do |spec|
            schema = spec.input_schema
            schema = schema.reject { |k, v| k == :required && Array(v).empty? }
            MCP_ADAPTER.tool(
              name: spec.verb.to_s,
              description: spec.summary,
              input_schema: schema,
            ) do |server_context:, **args|
              mcp_server.dispatch(spec.verb, args, server_context)
            end
          end
        end

        def names
          specs.map(&:verb).map(&:to_s)
        end

        def read_verbs
          Textus::Protocol::VerbRegistry.registered
                                        .select { |s| s.read? && s.mcp? }
                                        .map { |s| s.verb.to_s }
        end

        def write_verbs
          Textus::Protocol::VerbRegistry.registered
                                        .select { |s| s.write? && s.mcp? }
                                        .map { |s| s.verb.to_s }
        end

      end
    end
  end
end
