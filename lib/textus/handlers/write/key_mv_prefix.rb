module Textus
  module Handlers
    module Write
      module KeyMvPrefix
        HANDLES = Dispatch::Contracts::KeyMvPrefix
        NEEDS   = %i[orchestration].freeze

        def self.call(command, call, deps)
          if command.from_prefix.nil? || command.to_prefix.nil?
            return Value::Result.failure(:usage_error,
                                         "from_prefix and to_prefix required")
          end

          list = deps.orchestration.list_keys(prefix: command.from_prefix, lane: nil, call: call)
          return list if list.failure?

          leaves = list.value.fetch("rows")

          if leaves.any? { |r| r["key"] == command.from_prefix }
            return Value::Result.failure(:usage_error,
                                         "from_prefix '#{command.from_prefix}' is itself a leaf — use `mv` to rename a single key")
          end

          warnings = leaves.empty? ? ["no keys under #{command.from_prefix}"] : []
          steps = leaves.map do |row|
            old_key = row["key"]
            tail = old_key.delete_prefix("#{command.from_prefix}.")
            new_key = "#{command.to_prefix}.#{tail}"
            { "op" => "mv", "from" => old_key, "to" => new_key }
          end

          plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
          return Value::Result.success(plan) if command.dry_run

          steps.each do |step|
            move = deps.orchestration.move_key(old_key: step["from"], new_key: step["to"], call: call)
            return move if move.failure?
          end
          Value::Result.success(plan)
        end
      end
    end
  end
end
