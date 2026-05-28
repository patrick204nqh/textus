require "yaml"

module Textus
  module Application
    module Restructure
      # Loads a YAML migration plan and dispatches each op to the
      # appropriate Restructure use case. Concatenates resulting Plans.
      class Migrate
        OPS = {
          "key_mv_prefix" => KeyMvPrefix,
          "key_delete_prefix" => KeyDeletePrefix,
          "zone_mv" => ZoneMv,
        }.freeze

        def initialize(ctx:, caps:, operations:)
          @ctx        = ctx
          @caps       = caps
          @operations = operations
        end

        def call(plan_yaml:, dry_run: false)
          raw = YAML.safe_load(plan_yaml, permitted_classes: [Symbol], aliases: false)
          raise UsageError.new("migration plan must be a YAML mapping") unless raw.is_a?(Hash)

          ops = Array(raw["operations"])
          all_steps = []
          warnings = []

          ops.each do |op_hash|
            op_name = op_hash["op"]
            klass = OPS[op_name] or raise UsageError.new("unknown op: #{op_name}")
            sub_plan = invoke(klass, op_hash, dry_run: dry_run)
            all_steps.concat(sub_plan.steps)
            warnings.concat(sub_plan.warnings)
          end

          Plan.new(steps: all_steps, warnings: warnings)
        end

        private

        def invoke(klass, op_hash, dry_run:)
          args = op_hash.except("op").transform_keys(&:to_sym).merge(dry_run: dry_run)
          if klass.instance_method(:initialize).parameters.any? { |_t, n| n == :operations }
            klass.new(ctx: @ctx, caps: @caps, operations: @operations).call(**args)
          else
            klass.new(ctx: @ctx, caps: @caps).call(**args)
          end
        end
      end
    end
  end
end
