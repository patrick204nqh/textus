module Textus
  module Maintenance
    # Bulk-rename every leaf key under `from_prefix` to `to_prefix`.
    # Calls Write::Mv directly for each entry — emits one audit row per file moved.
    class KeyMvPrefix
      extend Textus::Contract::DSL

      verb     :key_mv_prefix
      summary  "Bulk-rename every leaf key under from_prefix to to_prefix. Dry-run returns a Plan; apply with dry_run: false."
      surfaces :cli, :ruby, :mcp
      cli      "key mv-prefix"
      arg :from_prefix, String, required: true, positional: true, description: "dotted prefix whose leaf keys are renamed"
      arg :to_prefix,   String, required: true, positional: true, description: "dotted prefix the keys are renamed to"
      arg :dry_run,     :boolean, default: false,
                                  description: "when true, returns the planned moves without applying them; " \
                                               "defaults to false, so omitting it applies the rename immediately"
      view { |v, _i| v.to_h }

      def initialize(container:, call:)
        @container    = container
        @call         = call
      end

      def call(from_prefix, to_prefix, dry_run: false)
        raise UsageError.new("from_prefix and to_prefix required") if from_prefix.nil? || to_prefix.nil?

        leaves = list_leaves_under(from_prefix)

        # When from_prefix is itself a leaf, `delete_prefix("#{from_prefix}.")`
        # finds no trailing dot to strip, so the tail keeps the whole key and the
        # move silently targets "to_prefix.<full-from_prefix>". Refuse it — a
        # single-key rename is `mv`'s job, not the bulk prefix verb's.
        if leaves.include?(from_prefix)
          raise UsageError.new("from_prefix '#{from_prefix}' is itself a leaf — use `mv` to rename a single key")
        end

        warnings = []
        warnings << "no keys under #{from_prefix}" if leaves.empty?

        steps = leaves.map do |old_key|
          tail = old_key.delete_prefix("#{from_prefix}.")
          new_key = "#{to_prefix}.#{tail}"
          { "op" => "mv", "from" => old_key, "to" => new_key }
        end

        plan = Plan.new(steps: steps, warnings: warnings)
        return plan if dry_run

        steps.each do |s|
          mv.call(s["from"], s["to"], dry_run: false)
        end
        plan
      end

      private

      def list_leaves_under(prefix)
        Read::List.new(container: @container)
                  .call(prefix: prefix)
                  .map { |row| row.is_a?(Hash) ? (row["key"] || row[:key]) : row }
      end

      def mv
        Write::Mv.new(container: @container, call: @call)
      end
    end
  end
end
