module Textus
  module Maintenance
    # Bulk-delete every leaf key under `prefix`.
    class KeyDeletePrefix
      extend Textus::Contract::DSL

      verb     :key_delete_prefix
      summary  "Bulk-delete every leaf key under prefix."
      surfaces :cli, :ruby, :mcp
      arg :prefix,  String, required: true
      arg :dry_run, :boolean
      response(&:to_h)

      def initialize(container:, call:)
        @container    = container
        @call         = call
      end

      def call(prefix:, dry_run: false)
        raise UsageError.new("prefix required") if prefix.nil? || prefix.empty?

        leaves = Read::List.new(container: @container)
                           .call(prefix: prefix)
                           .map { |r| r.is_a?(Hash) ? (r["key"] || r[:key]) : r }

        warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
        steps = leaves.map { |k| { "op" => "delete", "key" => k } }

        plan = Plan.new(steps: steps, warnings: warnings)
        return plan if dry_run

        steps.each do |s|
          delete.call(s["key"])
        end
        plan
      end

      private

      def delete
        Write::Delete.new(container: @container, call: @call)
      end
    end
  end
end
