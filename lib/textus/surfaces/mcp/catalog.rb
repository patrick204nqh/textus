module Textus
  module Surfaces
    module MCP
      # Derives the entire MCP tool surface from the per-verb contracts
      # (ADR 0039). `tool_schemas` feeds tools/list; `call` is the generic
      # tools/call dispatch: map JSON args -> (positional, keyword) per the
      # contract, invoke the verb through the role scope, then shape the
      # return value with the contract's default view. No per-tool code.
      module Catalog
        module_function

        WRITE_VERBS = %i[
          put propose key_delete key_mv accept reject enqueue
        ].freeze

        MAINTENANCE_VERBS = %i[
          data_mv key_mv_prefix key_delete_prefix drain rule_lint
        ].freeze

        # Contracts of every MCP-surfaced verb, in Dispatcher order.
        def specs
          Textus::Action::VERBS.values
                               .select { |k| mcp_surfaced?(k) }
                               .map(&:contract)
        end

        def tool_schemas
          specs.map do |s|
            { name: s.verb.to_s, description: s.summary, inputSchema: s.input_schema }
          end.freeze
        end

        def names
          specs.map { |s| s.verb.to_s }
        end

        # MCP-surfaced read verbs, by Dispatcher class namespace — the agent's
        # real read/discovery surface. `boot.agent_quickstart.read_verbs` derives
        # from this so it can never advertise a verb the agent cannot call, nor
        # omit one it can (ADR 0056). Excludes write/maintenance verbs by verb
        # identity (routing may be legacy UseCases or Dispatch::Actions).
        def read_verbs
          Textus::Action::VERBS
            .reject { |verb, _klass| WRITE_VERBS.include?(verb) || MAINTENANCE_VERBS.include?(verb) }
            .select { |_verb, klass| mcp_surfaced?(klass) }
            .keys.map(&:to_s)
        end

        # MCP-surfaced write verbs, by Dispatcher class namespace — the mirror of
        # read_verbs for the write side. `boot.agent_quickstart.write_verbs` derives
        # from this so it advertises bare verb names the agent can call (no `--as`/
        # `--stdin` CLI framing), finishing the de-CLI-ing of the agent surface
        # (ADR 0056, ADR 0057).
        def write_verbs
          Textus::Action::VERBS
            .select { |verb, klass| WRITE_VERBS.include?(verb) && mcp_surfaced?(klass) }
            .keys.map(&:to_s)
        end

        def mcp_surfaced?(klass)
          klass.respond_to?(:contract?) && klass.contract? && klass.contract.mcp?
        end

        def call(name, session:, store:, args:)
          klass = Textus::Action::VERBS[name.to_sym]
          raise ToolError.new("unknown tool: #{name}") unless klass && mcp_surfaced?(klass)

          spec = klass.contract
          inputs = Textus::Contract::Binder.inputs_from_wire(spec, args)
          cmd_class = Textus::Gate::VERB_COMMAND.fetch(spec.verb) do
            raise Textus::MCP::ToolError.new("unknown verb: #{spec.verb}")
          end
          cmd = cmd_class.new(**inputs.merge(role: session.role).slice(*cmd_class.members))
          result = store.gate.dispatch(cmd, container: store.container)
          Textus::Contract::View.render(spec, :default, result, inputs)
        rescue Textus::Contract::MissingArgs => e
          raise ToolError.new("#{spec.verb}: missing #{e.missing.map { |a| a.wire.to_s }.join(", ")}")
        rescue ContractDrift, CursorExpired
          raise
        rescue Textus::Error => e
          raise ToolError.new("#{name}: #{e.message}")
        end
      end
    end
  end
end
