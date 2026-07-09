module Textus
  module Protocol
    module Handlers
      module Ops
        class BulkPlanner
          Plan = Data.define(:steps, :warnings) do
            def to_h
              { "steps" => steps, "warnings" => warnings }
            end
          end

          def plan_mv(from_under:, to_under:, ctx:)
            raise Textus::UsageError.new("from_under and to_under required") unless from_under && to_under

            leaves = ctx.list(under: from_under)
            raise Textus::UsageError.new("from_under is a leaf — use mv") if leaves.any? { |r| r["key"] == from_under }

            warnings = leaves.empty? ? ["no keys under #{from_under}"] : []
            steps = leaves.map do |row|
              tail = row["key"].delete_prefix("#{from_under}.")
              { "op" => "mv", "from" => row["key"], "to" => "#{to_under}.#{tail}" }
            end
            Plan.new(steps:, warnings:)
          end

          def plan_delete(under:, ctx:)
            raise Textus::UsageError.new("under required") unless under && !under.empty?

            leaves = ctx.list(under:)
            warnings = leaves.empty? ? ["no keys under #{under}"] : []
            steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }
            Plan.new(steps:, warnings:)
          end
        end
      end
    end
  end
end
