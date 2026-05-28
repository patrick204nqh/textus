module Textus
  module Application
    module Restructure
      # Bulk-delete every leaf key under `prefix`.
      class KeyDeletePrefix
        def initialize(ctx:, store:)
          @ctx   = ctx
          @store = store
        end

        def call(prefix:, dry_run: false)
          raise UsageError.new("prefix required") if prefix.nil? || prefix.empty?

          leaves = Reads::List.new(manifest: @store.manifest)
                              .call(prefix: prefix)
                              .map { |r| r.is_a?(Hash) ? (r["key"] || r[:key]) : r }

          warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
          steps = leaves.map { |k| { "op" => "delete", "key" => k } }

          plan = Plan.new(steps: steps, warnings: warnings)
          return plan if dry_run

          ops = Operations.for(@store, role: @ctx.role, correlation_id: @ctx.correlation_id)
          steps.each { |s| ops.delete(s["key"]) }
          plan
        end
      end
    end
  end
end
