module Textus
  module Protocol
    module Handlers
      module Ops
        class BulkPlanner
          def plan_mv(from_prefix:, to_prefix:, ctx:)
            raise Textus::UsageError.new("from_prefix and to_prefix required") unless from_prefix && to_prefix

            leaves = ctx.list(prefix: from_prefix)
            raise Textus::UsageError.new("from_prefix is a leaf — use mv") if leaves.any? { |r| r["key"] == from_prefix }

            warnings = leaves.empty? ? ["no keys under #{from_prefix}"] : []
            steps = leaves.map do |row|
              tail = row["key"].delete_prefix("#{from_prefix}.")
              { "op" => "mv", "from" => row["key"], "to" => "#{to_prefix}.#{tail}" }
            end
            Textus::Protocol::Retention::Plan.new(steps:, warnings:)
          end

          def plan_delete(prefix:, ctx:)
            raise Textus::UsageError.new("prefix required") unless prefix && !prefix.empty?

            leaves = ctx.list(prefix:)
            warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
            steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }
            Textus::Protocol::Retention::Plan.new(steps:, warnings:)
          end
        end
      end
    end
  end
end
