module Textus
  module MCP
    # Derives the entire MCP tool surface from the per-verb contracts
    # (ADR 0039). `tool_schemas` feeds tools/list; `call` is the generic
    # tools/call dispatch: map JSON args -> (positional, keyword) per the
    # contract, invoke the verb through the role scope, then shape the
    # return value with the contract's response block. No per-tool code.
    module Catalog
      module_function

      # Contracts of every MCP-surfaced verb, in Dispatcher order.
      def specs
        Textus::Dispatcher::VERBS.values
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
      # omit one it can (ADR 0056). Excludes Write/Maintenance.
      def read_verbs
        Textus::Dispatcher::VERBS
          .select { |_verb, klass| mcp_surfaced?(klass) && klass.name.start_with?("Textus::Read::") }
          .keys.map(&:to_s)
      end

      # MCP-surfaced write verbs, by Dispatcher class namespace — the mirror of
      # read_verbs for the write side. `boot.agent_quickstart.write_verbs` derives
      # from this so it advertises bare verb names the agent can call (no `--as`/
      # `--stdin` CLI framing), finishing the de-CLI-ing of the agent surface
      # (ADR 0056, ADR 0057).
      def write_verbs
        Textus::Dispatcher::VERBS
          .select { |_verb, klass| mcp_surfaced?(klass) && klass.name.start_with?("Textus::Write::") }
          .keys.map(&:to_s)
      end

      def mcp_surfaced?(klass)
        klass.respond_to?(:contract?) && klass.contract? && klass.contract.mcp?
      end

      def call(name, session:, store:, args:)
        klass = Textus::Dispatcher::VERBS[name.to_sym]
        raise ToolError.new("unknown tool: #{name}") unless klass && mcp_surfaced?(klass)

        spec = klass.contract
        pos, kw = map_args(spec, args || {}, session)
        result = store.as(session.role).public_send(spec.verb, *pos, **kw)
        spec.response.call(result)
      rescue ContractDrift, CursorExpired
        raise
      rescue Textus::Error => e
        raise ToolError.new("#{name}: #{e.message}")
      end

      # Normalizes the raw JSON arg hash (keyed by wire-name) into the uniform
      # by-name inputs hash, then delegates the split-and-default algorithm to
      # the shared Contract::Binder. Session-default args are injected from the
      # session when absent; the missing-arg error is translated to ToolError
      # with the same wording the MCP wire has always spoken.
      def map_args(spec, raw, session = nil)
        inputs = spec.args.each_with_object({}) do |a, h|
          h[a.name] = raw[a.wire.to_s] if raw.key?(a.wire.to_s)
        end
        Textus::Contract::Binder.bind(spec, inputs, session: session)
      rescue Textus::Contract::MissingArgs => e
        raise ToolError.new("#{spec.verb}: missing #{e.missing.map { |a| a.wire.to_s }.join(", ")}")
      end
    end
  end
end
