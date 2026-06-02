module Textus
  module Read
    # Enumerate every declared rule block in the manifest, in order. This is
    # the whole-manifest view; `rule_explain` is the for-key view. Extracted
    # from the CLI verb so the rule family is fully use-case-backed (ADR 0059);
    # CLI-only (no MCP contract) — an agent reasons per-key via rule_explain.
    class RuleList
      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call
        @manifest.rules.blocks.map do |b|
          row = { "match" => b.match }
          if b.fetch
            row["fetch"] = {
              "ttl_seconds" => b.fetch.ttl_seconds,
              "on_stale" => b.fetch.on_stale,
              "sync_budget_ms" => b.fetch.sync_budget_ms,
              "fetch_timeout_seconds" => b.fetch.fetch_timeout_seconds,
            }
          end
          row["handler_allowlist"] = b.handler_allowlist.handlers if b.handler_allowlist
          row["guard"] = b.guard if b.guard
          row["retention"] = { "expire_after" => b.retention.expire_after, "archive_after" => b.retention.archive_after } if b.retention
          row
        end
      end
    end
  end
end
