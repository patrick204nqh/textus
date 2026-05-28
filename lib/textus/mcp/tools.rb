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
        store.session(role: session.role)
      end

      REGISTRY = {
        "boot" => ->(_s, store, _a) { Textus::Boot.run(Textus::Session.for(store)) },

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

        "refresh" => lambda do |s, store, args|
          key = args.fetch("key") { raise ToolError.new("refresh: missing key") }
          outcome = ops_for(s, store).refresh(key)
          { "outcome" => outcome.class.name.split("::").last.downcase }
        end,

        "refresh_stale" => lambda do |s, store, args|
          ops_for(s, store).refresh_all(zone: args["zone"], prefix: args["prefix"])
        end,

        "schema" => lambda do |_s, store, args|
          family = args.fetch("family") { raise ToolError.new("schema: missing family") }
          store.schemas.fetch(family)
        end,

        "rules" => lambda do |_s, store, args|
          key = args.fetch("key") { raise ToolError.new("rules: missing key") }
          set = store.manifest.rules.for(key)
          {
            "refresh" => set.refresh&.to_h,
            "promote" => set.respond_to?(:promote) ? set.promote&.to_h : nil,
          }.compact
        end,

        "key_mv_prefix" => lambda do |s, store, args|
          ops_for(s, store).key_mv_prefix(
            from_prefix: args.fetch("from_prefix") { raise ToolError.new("key_mv_prefix: missing from_prefix") },
            to_prefix: args.fetch("to_prefix") { raise ToolError.new("key_mv_prefix: missing to_prefix") },
            dry_run: args["dry_run"] || false,
          ).to_h
        end,

        "key_delete_prefix" => lambda do |s, store, args|
          ops_for(s, store).key_delete_prefix(
            prefix: args.fetch("prefix") { raise ToolError.new("key_delete_prefix: missing prefix") },
            dry_run: args["dry_run"] || false,
          ).to_h
        end,

        "zone_mv" => lambda do |s, store, args|
          ops_for(s, store).zone_mv(
            from: args.fetch("from") { raise ToolError.new("zone_mv: missing from") },
            to: args.fetch("to") { raise ToolError.new("zone_mv: missing to") },
            dry_run: args["dry_run"] || false,
          ).to_h
        end,

        "rule_lint" => lambda do |s, store, args|
          ops_for(s, store).rule_lint(
            candidate_yaml: args.fetch("candidate_yaml") { raise ToolError.new("rule_lint: missing candidate_yaml") },
          ).to_h
        end,

        "migrate" => lambda do |s, store, args|
          ops_for(s, store).migrate(
            plan_yaml: args.fetch("plan_yaml") { raise ToolError.new("migrate: missing plan_yaml") },
            dry_run: args["dry_run"] || false,
          ).to_h
        end,
      }.freeze
    end
  end
end
