module Textus
  module Application
    module Maintenance
      # Bulk-delete every leaf key under `prefix`.
      module KeyDeletePrefix
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(ctx: ctx, caps: caps, session: session).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, session:)
            @ctx     = ctx
            @caps    = caps
            @session = session
          end

          def call(prefix:, dry_run: false)
            raise UsageError.new("prefix required") if prefix.nil? || prefix.empty?

            leaves = Read::List::Impl.new(caps: @caps)
                                     .call(prefix: prefix)
                                     .map { |r| r.is_a?(Hash) ? (r["key"] || r[:key]) : r }

            warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
            steps = leaves.map { |k| { "op" => "delete", "key" => k } }

            plan = Plan.new(steps: steps, warnings: warnings)
            return plan if dry_run

            steps.each do |s|
              @session.delete(s["key"])
            end
            plan
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:key_delete_prefix, Textus::Application::Maintenance::KeyDeletePrefix, caps: :write)
