module Textus
  module MCP
    # Dispatch table for MCP tool names → implementations. Each implementation
    # receives (session:, store:, args:) and returns a JSON-encodable value.
    # Tool errors are wrapped in ToolError; ContractDrift / CursorExpired
    # propagate verbatim so the server can map them to JSON-RPC codes.
    module Tools
      module_function

      def call(name, session:, store:, args:)
        impl = REGISTRY[name] or raise ToolError.new("unknown tool: #{name}")
        impl.call(session, store, args || {})
      rescue ContractDrift, CursorExpired
        raise
      rescue Textus::Error => e
        raise ToolError.new("#{name}: #{e.message}")
      end

      def ops_for(session, store)
        Textus::Operations.for(store, role: session.role)
      end

      REGISTRY = {
        "boot" => ->(_s, store, _a) { Textus::Boot.run(store) },

        "find" => lambda do |s, store, args|
          ops_for(s, store).list(zone: args["zone"], prefix: args["prefix"])
        end,

        "read" => lambda do |s, store, args|
          key = args.fetch("key") { raise ToolError.new("read: missing key") }
          env = ops_for(s, store).get(key)
          env.to_h_for_wire
        end,

        "tick" => lambda do |s, store, args|
          since = (args["since"] || s.cursor).to_i
          ops_for(s, store).pulse(since: since)
        end,

        "write" => lambda do |s, store, args|
          key = args.fetch("key") { raise ToolError.new("write: missing key") }
          env = ops_for(s, store).put(
            key,
            meta: args["meta"] || {},
            body: args["body"],
            content: args["content"],
            if_etag: args["if_etag"],
          )
          { "uid" => env.uid, "etag" => env.etag }
        end,

        "propose" => lambda do |s, store, args|
          raise ToolError.new("propose: session has no propose_zone") unless s.propose_zone

          rel = args.fetch("key") { raise ToolError.new("propose: missing key") }
          target = "#{s.propose_zone}.#{rel}"
          env = ops_for(s, store).put(
            target,
            meta: args["meta"] || {},
            body: args["body"],
            content: args["content"],
          )
          { "uid" => env.uid, "etag" => env.etag, "key" => target }
        end,
      }.freeze
    end
  end
end
