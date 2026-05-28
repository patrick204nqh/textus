module Textus
  module Application
    module Restructure
      # Bulk-delete every leaf key under `prefix`.
      module KeyDeletePrefix
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(ctx: ctx, caps: caps, operations: session).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, operations:)
            @ctx        = ctx
            @caps       = caps
            @operations = operations
          end

          def call(prefix:, dry_run: false)
            raise UsageError.new("prefix required") if prefix.nil? || prefix.empty?

            leaves = Reads::List::Impl.new(caps: @caps)
                                      .call(prefix: prefix)
                                      .map { |r| r.is_a?(Hash) ? (r["key"] || r[:key]) : r }

            warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
            steps = leaves.map { |k| { "op" => "delete", "key" => k } }

            plan = Plan.new(steps: steps, warnings: warnings)
            return plan if dry_run

            steps.each { |s| @operations.delete(s["key"]) }
            plan
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:key_delete_prefix, Textus::Application::Restructure::KeyDeletePrefix, caps: :write)
