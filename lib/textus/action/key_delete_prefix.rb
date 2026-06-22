# frozen_string_literal: true

module Textus
  module Action
    class KeyDeletePrefix < Base
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

      def self.call(container:, call:, prefix:, dry_run: false)
        return Failure(code: :usage_error, message: "prefix required") if prefix.nil? || prefix.empty?

        leaves = Textus::Action::List.leaf_keys(container: container, prefix: prefix)

        warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
        steps = leaves.map { |key| { "op" => "delete", "key" => key } }

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
        return Success(plan) if dry_run

        steps.each do |step|
          Value::Result.unwrap(Textus::Action::KeyDelete.call(container: container, call: call, key: step["key"]))
        end
        Success(plan)
      end
    end
  end
end
