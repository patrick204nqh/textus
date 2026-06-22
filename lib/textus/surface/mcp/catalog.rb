module Textus
  module Surface
    module MCP
      module Catalog
        PROJECTOR = Projector.new(view_key: :default, binder_method: :inputs_from_wire).freeze

        module_function

        WRITE_VERBS = %i[
          put propose key_delete key_mv accept reject enqueue
        ].freeze

        MAINTENANCE_VERBS = %i[
          data_mv key_mv_prefix key_delete_prefix drain rule_lint
        ].freeze

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
            .reject { |s| WRITE_VERBS.include?(s.verb) || MAINTENANCE_VERBS.include?(s.verb) }
            .select(&:mcp?)
            .map { |s| s.verb.to_s }
        end

        def write_verbs
          VerbRegistry.registered
            .select { |s| WRITE_VERBS.include?(s.verb) && s.mcp? }
            .map { |s| s.verb.to_s }
        end

        def call(name, session:, store:, args:)
          spec = VerbRegistry.for(name.to_sym)
          raise ToolError.new("unknown tool: #{name}") unless spec&.mcp?

          PROJECTOR.dispatch(name, inputs: args, store:, role: session.role, session:)
        rescue Textus::Bus::MissingArgs => e
          raise ToolError.new("#{name}: missing #{e.missing.map { |a| a.wire.to_s }.join(", ")}")
        rescue Textus::ContractDrift, CursorExpired
          raise
        rescue Textus::Error => e
          raise ToolError.new("#{name}: #{e.message}")
        end
      end
    end
  end
end
