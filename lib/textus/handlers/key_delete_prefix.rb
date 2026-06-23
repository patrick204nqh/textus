module Textus
  module Handlers
    class KeyDeletePrefix
      def initialize(orchestration:)
        @orchestration = orchestration
      end

      def call(command, call)
        return Value::Result.failure(:usage_error, "prefix required") if command.prefix.nil? || command.prefix.empty?

        list = @orchestration.list_keys(prefix: command.prefix, lane: nil, call: call)
        return list if list.failure?

        leaves = list.value.fetch("rows")

        warnings = leaves.empty? ? ["no keys under #{command.prefix}"] : []
        steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
        return Value::Result.success(plan) if command.dry_run

        steps.each do |step|
          delete = @orchestration.delete_key(key: step["key"], call: call)
          return delete if delete.failure?
        end
        Value::Result.success(plan)
      end
    end
  end
end
