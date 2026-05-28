module Textus
  module Application
    module Maintenance
      # Bulk-rename every leaf key under `from_prefix` to `to_prefix`.
      # Calls Write::Mv directly for each entry — emits one audit row per file moved.
      module KeyMvPrefix
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(ctx: ctx, caps: caps, session: session).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, session:)
            @ctx     = ctx
            @caps    = caps
            @session = session
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
              Textus::Application::Write::Mv.call(
                s["from"], s["to"],
                session: @session, ctx: @ctx, caps: @session.write_caps,
                dry_run: false
              )
            end
            plan
          end

          private

          def list_leaves_under(prefix)
            Read::List::Impl.new(caps: @caps)
                            .call(prefix: prefix)
                            .map { |row| row.is_a?(Hash) ? (row["key"] || row[:key]) : row }
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:key_mv_prefix, Textus::Application::Maintenance::KeyMvPrefix, caps: :write)
