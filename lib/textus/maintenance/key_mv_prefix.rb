module Textus
  module Maintenance
    # Bulk-rename every leaf key under `from_prefix` to `to_prefix`.
    # Calls Write::Mv directly for each entry — emits one audit row per file moved.
    class KeyMvPrefix
      extend Textus::Contract::DSL

      verb     :key_mv_prefix
      summary  "Bulk-rename every leaf key under from_prefix to to_prefix. Dry-run returns a Plan; apply with dry_run: false."
      surfaces :cli, :ruby, :mcp
      arg :from_prefix, String, required: true
      arg :to_prefix,   String, required: true
      arg :dry_run,     :boolean
      response(&:to_h)

      def initialize(container:, call:)
        @container    = container
        @call         = call
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
