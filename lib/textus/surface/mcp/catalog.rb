module Textus
  module Surface
    module MCP
      module Catalog
        PROJECTOR = Projector.new(view_key: :default).freeze

        module_function

        def specs
          VerbRegistry.registered.select(&:mcp?)
        end

        def build_tools(mcp_server)
          specs.map do |spec|
            schema = spec.input_schema
            schema = schema.reject { |k, v| k == :required && Array(v).empty? }
            ::MCP::Tool.define(
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
          VerbRegistry.registered
                      .select { |s| s.read? && s.mcp? }
                      .map { |s| s.verb.to_s }
        end

        def write_verbs
          VerbRegistry.registered
                      .select { |s| s.write? && s.mcp? }
                      .map { |s| s.verb.to_s }
        end

        def call(name, store:, args:)
          spec = VerbRegistry.for(name.to_sym)
          raise ToolError.new("unknown tool: #{name}") unless spec&.mcp?

          PROJECTOR.dispatch(name, inputs: args, store:)
        rescue Textus::Dispatch::MissingArgs => e
          raise ToolError.new("#{name}: missing #{e.missing.map { |a| a.wire.to_s }.join(", ")}")
        rescue Textus::ContractDrift, Textus::CursorExpired
          raise
        rescue Textus::Error => e
          raise ToolError.new("#{name}: #{e.message}")
        end
      end
    end
  end
end
