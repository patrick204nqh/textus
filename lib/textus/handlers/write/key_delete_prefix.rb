module Textus
  module Handlers
    module Write
      module KeyDeletePrefix
        HANDLES = Dispatch::Contracts::KeyDeletePrefix
        NEEDS   = %i[orchestration].freeze

        def self.call(command, call, deps)
          return Value::Result.failure(:usage_error, "prefix required") if command.prefix.nil? || command.prefix.empty?

          list = deps.orchestration.list_keys(prefix: command.prefix, lane: nil, call: call)
          return list if list.failure?

          leaves = list.value.fetch("rows")

          warnings = leaves.empty? ? ["no keys under #{command.prefix}"] : []
          steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }

          plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
          return Value::Result.success(plan) if command.dry_run

          steps.each do |step|
            delete = deps.orchestration.delete_key(key: step["key"], call: call)
            return delete if delete.failure?
          end
          Value::Result.success(plan)
        end
      end
    end
  end
end
