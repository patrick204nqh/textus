module Textus
  module Application
    module Restructure
      # Bulk-rename every leaf key under `from_prefix` to `to_prefix`.
      # Reuses Operations#mv for the per-entry work — emits one audit
      # row per file moved.
      class KeyMvPrefix
        def initialize(ctx:, caps:, operations:)
          @ctx        = ctx
          @caps       = caps
          @operations = operations
        end

        def call(from_prefix:, to_prefix:, dry_run: false)
          raise UsageError.new("from_prefix and to_prefix required") if from_prefix.nil? || to_prefix.nil?

          leaves = list_leaves_under(from_prefix)
          warnings = []
          warnings << "no keys under #{from_prefix}" if leaves.empty?

          steps = leaves.map do |old_key|
            tail = old_key.delete_prefix("#{from_prefix}.")
            new_key = "#{to_prefix}.#{tail}"
            { "op" => "mv", "from" => old_key, "to" => new_key }
          end

          plan = Plan.new(steps: steps, warnings: warnings)
          return plan if dry_run

          steps.each { |s| @operations.mv(s["from"], s["to"], dry_run: false) }
          plan
        end

        private

        def list_leaves_under(prefix)
          Reads::List.new(caps: @caps)
                     .call(prefix: prefix)
                     .map { |row| row.is_a?(Hash) ? (row["key"] || row[:key]) : row }
        end
      end
    end
  end
end
