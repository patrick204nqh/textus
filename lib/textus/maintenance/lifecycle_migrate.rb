require "yaml"

module Textus
  module Maintenance
    # Rewrite legacy fetch:/retention: rule slots into the unified lifecycle:
    # slot (ADR 0079). Load -> mutate -> dump, like ZoneMv; --dry-run + Plan,
    # like KeyDeletePrefix. A block with both fetch: and retention: is split
    # into two same-match blocks (one refresh, one drop/archive).
    class LifecycleMigrate
      extend Textus::Contract::DSL

      verb     :lifecycle_migrate
      summary  "Rewrite legacy fetch:/retention: rule slots into the unified lifecycle: slot."
      surfaces :cli, :mcp
      cli      "lifecycle migrate"
      arg :dry_run, :boolean, default: false,
                              description: "when true, return the rewrite plan without writing manifest.yaml"
      view { |v, _i| v.to_h }

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(dry_run: false)
        path = File.join(@container.root.to_s, "manifest.yaml")
        doc  = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: false) || {}
        rules = doc["rules"] || []

        steps     = []
        warnings  = []
        rewritten = rules.flat_map { |block| rewrite_block(block, steps, warnings) }

        plan = Plan.new(steps: steps, warnings: warnings)
        return plan if dry_run

        doc["rules"] = rewritten
        File.write(path, YAML.dump(doc))
        plan
      end

      private

      def rewrite_block(block, steps, warnings)
        has_fetch     = block.key?("fetch")
        has_retention = block.key?("retention")
        return [block] unless has_fetch || has_retention

        out = []
        if has_fetch
          out << lifecycle_block(block, fetch_lifecycle(block["fetch"]))
          steps << { "match" => block["match"], "from" => "fetch", "to" => "lifecycle" }
        end
        if has_retention
          out << lifecycle_block(block, retention_lifecycle(block["retention"], warnings, block["match"]))
          steps << { "match" => block["match"], "from" => "retention", "to" => "lifecycle" }
        end
        warnings << both_warning(block["match"]) if has_fetch && has_retention
        out
      end

      def both_warning(match)
        "block #{match.inspect} had both fetch+retention; split into two blocks"
      end

      def lifecycle_block(block, lifecycle)
        block.except("fetch", "retention").merge("lifecycle" => lifecycle)
      end

      def fetch_lifecycle(h)
        on_expire = %w[sync timed_sync].include?(h["on_stale"].to_s) ? "refresh" : "warn"
        lc = { "ttl" => h["ttl"], "on_expire" => on_expire }
        lc["budget_ms"] = h["sync_budget_ms"] if h["sync_budget_ms"]
        lc
      end

      def retention_lifecycle(h, warnings, match)
        if h["expire_after"]
          warnings << "block #{match.inspect} archive_after dropped (collapsed to expire_after)" if h["archive_after"]
          { "ttl" => h["expire_after"], "on_expire" => "drop" }
        else
          { "ttl" => h["archive_after"], "on_expire" => "archive" }
        end
      end
    end
  end
end
