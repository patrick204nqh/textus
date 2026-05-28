require "yaml"

module Textus
  module Application
    module Maintenance
      # Loads a YAML migration plan and dispatches each op to the
      # appropriate Maintenance use case. Concatenates resulting Plans.
      module Migrate
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(ctx: ctx, caps: caps, session: session).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, session:)
            @ctx     = ctx
            @caps    = caps
            @session = session
          end

          def call(plan_yaml:, dry_run: false)
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
            kwargs = op_hash.except("op").transform_keys(&:to_sym).merge(dry_run: dry_run)
            case op_name
            when "key_mv_prefix"
              KeyMvPrefix.call(session: @session, ctx: @ctx, caps: @caps, **kwargs)
            when "key_delete_prefix"
              KeyDeletePrefix.call(session: @session, ctx: @ctx, caps: @caps, **kwargs)
            when "zone_mv"
              ZoneMv.call(session: @session, ctx: @ctx, caps: @caps, **kwargs)
            else
              raise UsageError.new("unknown op: #{op_name}")
            end
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:migrate, Textus::Application::Maintenance::Migrate, caps: :write)
