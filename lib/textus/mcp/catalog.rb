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

      # Splits the raw JSON arg hash into the positional list and keyword hash
      # the use-case expects, validating required presence first.
      # Session-default args (session_default: :method_name) are injected from
      # the session when absent from the wire; they are never treated as missing.
      # Positional args are emitted in contract declaration order; use-case signatures must match.
      def map_args(spec, raw, session = nil)
        missing = spec.required_args.map { |a| a.wire.to_s } - raw.keys
        raise ToolError.new("#{spec.verb}: missing #{missing.join(", ")}") unless missing.empty?

        positional = []
        keyword = {}
        spec.args.each do |a|
          if raw.key?(a.wire.to_s)
            value = raw[a.wire.to_s]
          elsif a.session_default && session
            value = session.public_send(a.session_default)
          else
            next
          end

          if a.positional
            positional << value
          else
            keyword[a.name] = value
          end
        end
        [positional, keyword]
      end
    end
  end
end
