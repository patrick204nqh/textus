module Textus
  module UseCases
    module Write
      module KeyDeletePrefix
        HANDLES = Dispatch::Contracts::KeyDeletePrefix
        NEEDS = %i[file_store manifest schemas audit_log layout job_store].freeze

        def self.call(command, call, deps)
          return Value::Result.failure(:usage_error, "prefix required") if command.prefix.nil? || command.prefix.empty?

          list_cmd = Data.define(:prefix, :lane, :q, :schema).new(
            prefix: command.prefix, lane: nil, q: nil, schema: nil,
          )
          list = UseCases::Read::ListKeys.call(list_cmd, call, deps)
          return list if list.failure?

          leaves = list.value || []

          warnings = leaves.empty? ? ["no keys under #{command.prefix}"] : []
          steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }

          plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
          return Value::Result.success(plan) if command.dry_run

          steps.each do |step|
            delete = DeleteKey.call(
              Data.define(:key, :if_etag).new(
                key: step["key"], if_etag: nil,
              ),
              call,
              deps,
            )
            return delete if delete.failure?
          end
          Value::Result.success(plan)
        end
      end
    end
  end
end
