# frozen_string_literal: true

module Textus
  module Action
    class KeyDeletePrefix < Base
      extend Textus::Contract::DSL

      verb :key_delete_prefix
      summary "Bulk-delete every leaf key under prefix."
      surfaces :cli, :mcp
      cli "key delete-prefix"
      arg :prefix, String, required: true, positional: true,
                           description: "every leaf key under this dotted prefix is deleted"
      arg :dry_run, :boolean, default: false,
                              description: "when true, returns the keys that would be deleted without deleting them; " \
                                           "defaults to false, so omitting it deletes immediately"
      view { |v, _i| v.to_h }

      BURN = :sync

      def initialize(prefix:, dry_run: false)
        super()
        @prefix = prefix
        @dry_run = dry_run
      end

      def args
        {
          prefix: @prefix,
          dry_run: @dry_run,
        }
      end

      def call(container:, call:)
        raise UsageError.new("prefix required") if @prefix.nil? || @prefix.empty?

        leaves = Textus::Action::List.new(prefix: @prefix).call(container: container)
                                     .map { |row| row.is_a?(Hash) ? (row["key"] || row[:key]) : row }

        warnings = leaves.empty? ? ["no keys under #{@prefix}"] : []
        steps = leaves.map { |key| { "op" => "delete", "key" => key } }

        plan = Textus::Dispatch::Runtime::Plan.new(steps: steps, warnings: warnings)
        return plan if @dry_run

        steps.each do |step|
          Textus::Action::KeyDelete.new(key: step["key"]).call(container: container, call: call)
        end
        plan
      end
    end
  end
end
