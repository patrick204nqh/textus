# frozen_string_literal: true

module Textus
  module Action
    class KeyMvPrefix < Base
      extend Textus::Contract::DSL

      verb :key_mv_prefix
      summary "Bulk-rename every leaf key under from_prefix to to_prefix. Dry-run returns a Plan; apply with dry_run: false."
      surfaces :cli, :mcp
      cli "key mv-prefix"
      arg :from_prefix, String, required: true, positional: true,
                                description: "dotted prefix whose leaf keys are renamed"
      arg :to_prefix, String, required: true, positional: true,
                              description: "dotted prefix the keys are renamed to"
      arg :dry_run, :boolean, default: false,
                              description: "when true, returns the planned moves without applying them; defaults " \
                                           "to false, so omitting it applies the rename immediately"
      view { |v, _i| v.to_h }

      def self.call(container:, call:, from_prefix:, to_prefix:, dry_run: false)
        raise UsageError.new("from_prefix and to_prefix required") if from_prefix.nil? || to_prefix.nil?

        leaves = Textus::Action::List.leaf_keys(container: container, prefix: from_prefix)

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

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
        return plan if dry_run

        steps.each do |step|
          Textus::Action::KeyMv.call(container: container, call: call, old_key: step["from"], new_key: step["to"])
        end
        plan
      end
    end
  end
end
