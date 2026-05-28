module Textus
  module MCP
    # JSON-Schema definitions for every MCP tool's inputSchema. Returned by
    # the server in tools/list. Static today — a follow-up will enrich with
    # manifest-derived enums for `zone`, `key`, etc.
    module ToolSchemas
      module_function

      def all # rubocop:disable Metrics/MethodLength
        [
          tool("boot", "Return the orientation contract: zones, entries, schemas, write_flows, agent_quickstart.", {}, []),
          tool("tick", "Delta since cursor. Returns {cursor, changed, stale, pending_review, doctor}.",
               { "since" => { "type" => "integer", "minimum" => 0 } }, []),
          tool("find", "List keys filtered by zone and/or prefix.",
               { "zone" => { "type" => "string" }, "prefix" => { "type" => "string" } }, []),
          tool("read", "Read one entry. Returns the envelope (uid, etag, _meta, body, freshness).",
               { "key" => { "type" => "string" } }, ["key"]),
          tool("write", "Create or update an entry. Schema-validated. Returns {uid, etag}.",
               {
                 "key" => { "type" => "string" },
                 "meta" => { "type" => "object" },
                 "body" => { "type" => "string" },
                 "content" => { "type" => "object" },
                 "if_etag" => { "type" => "string" },
               }, %w[key meta]),
          tool("propose", "Write a proposal to the session's propose_zone. Auto-prefixes the key.",
               {
                 "key" => { "type" => "string", "description" => "Key relative to propose_zone, e.g. 'proposal.feature-x'" },
                 "meta" => { "type" => "object" },
                 "body" => { "type" => "string" },
               }, %w[key meta]),
          tool("refresh", "Run an intake refresh for one key. Returns the refresh Outcome.",
               { "key" => { "type" => "string" } }, ["key"]),
          tool("refresh_stale", "Refresh all stale intake entries, optionally scoped by zone/prefix.",
               {
                 "zone" => { "type" => "string" },
                 "prefix" => { "type" => "string" },
               }, []),
          tool("schema", "Return the schema (field shape) for an entry family.",
               { "family" => { "type" => "string" } }, ["family"]),
          tool("rules", "Return effective rules for a key (refresh, promote, ...).",
               { "key" => { "type" => "string" } }, ["key"]),
          tool("key_mv_prefix",
               "Bulk-rename every leaf key under from_prefix to to_prefix. Dry-run returns a Plan; apply with dry_run: false.",
               { "from_prefix" => { "type" => "string" }, "to_prefix" => { "type" => "string" }, "dry_run" => { "type" => "boolean" } },
               %w[from_prefix to_prefix]),
          tool("key_delete_prefix", "Bulk-delete every leaf key under prefix.",
               { "prefix" => { "type" => "string" }, "dry_run" => { "type" => "boolean" } },
               ["prefix"]),
          tool("zone_mv", "Rename a zone — manifest + files. Refuses if destination exists.",
               { "from" => { "type" => "string" }, "to" => { "type" => "string" }, "dry_run" => { "type" => "boolean" } },
               %w[from to]),
          tool("rule_lint", "Diff candidate manifest YAML's rules against the live manifest. No writes.",
               { "candidate_yaml" => { "type" => "string" } },
               ["candidate_yaml"]),
          tool("migrate", "Run a YAML migration plan (multi-op).",
               { "plan_yaml" => { "type" => "string" }, "dry_run" => { "type" => "boolean" } },
               ["plan_yaml"]),
        ].freeze
      end

      def tool(name, description, properties, required)
        {
          name: name,
          description: description,
          inputSchema: { type: "object", properties: properties, required: required },
        }
      end
    end
  end
end
