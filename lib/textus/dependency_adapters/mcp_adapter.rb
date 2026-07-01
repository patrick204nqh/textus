module Textus
  module DependencyAdapters
    class McpAdapter
      def server(name:, version:, tools:, resources:, server_context:)
        ::MCP::Server.new(
          name: name,
          version: version,
          tools: tools,
          resources: resources,
          server_context: server_context,
        )
      end

      def tool(name:, description:, input_schema:, &)
        ::MCP::Tool.define(
          name: name,
          description: description,
          input_schema: input_schema,
          &
        )
      end
    end
  end
end
