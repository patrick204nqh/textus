require "yaml"

module Textus
  module Maintenance
    # Loads a YAML migration plan and dispatches each op to the
    # appropriate Maintenance use case. Concatenates resulting Plans.
    class Migrate
      extend Textus::Contract::DSL

      verb     :migrate
      summary  "Run a YAML migration plan (multi-op)."
      surfaces :cli, :ruby, :mcp
      arg :plan_yaml, String, required: true, positional: true, source: :file,
                              description: "path to the YAML migration plan (zone_mv, key_mv_prefix, key_delete_prefix ops run in order)"
      arg :dry_run, :boolean, default: false,
                              description: "when true, returns the planned ops without applying them; " \
                                           "defaults to false, so omitting it runs the migration immediately"
      view { |v, _i| v.to_h }

      def initialize(container:, call:)
        @container    = container
        @call         = call
      end

      def call(plan_yaml, dry_run: false)
        raw = YAML.safe_load(plan_yaml, permitted_classes: [Symbol], aliases: false)
        raise UsageError.new("migration plan must be a YAML mapping") unless raw.is_a?(Hash)

        ops = Array(raw["operations"])
        all_steps = []
        warnings = []

        ops.each do |op_hash|
          op_name = op_hash["op"]
          sub_plan = invoke_op(op_name, op_hash, dry_run: dry_run)
          all_steps.concat(sub_plan.steps)
          warnings.concat(sub_plan.warnings)
        end

        Plan.new(steps: all_steps, warnings: warnings)
      end

      private

      def invoke_op(op_name, op_hash, dry_run:)
        klass = op_class(op_name)
        inputs = op_hash.except("op").transform_keys(&:to_sym).merge(dry_run: dry_run)
        # Each op now carries positional args (from/to, from_prefix/to_prefix,
        # prefix); split the YAML fields into (positional, keyword) via the op's
        # own contract so we call its #call signature correctly (ADR 0066/0068).
        args, kwargs = Textus::Contract::Binder.bind(klass.contract, inputs)
        klass.new(container: @container, call: @call).call(*args, **kwargs)
      end

      def op_class(op_name)
        case op_name
        when "key_mv_prefix"     then KeyMvPrefix
        when "key_delete_prefix" then KeyDeletePrefix
        when "zone_mv"           then ZoneMv
        else raise UsageError.new("unknown op: #{op_name}")
        end
      end
    end
  end
end
