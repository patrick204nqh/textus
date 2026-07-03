module Textus
  module UseCases
    module Write
      class KeyDeletePrefix < Base
        handles Dispatch::Contracts::KeyDeletePrefix
        needs :file_system, :manifest, :schemas, :audit_log, :layout, :writer, :reader

        def call
          return failure(:usage_error, "prefix required") if command.prefix.nil? || command.prefix.empty?

          list_cmd = Data.define(:prefix, :lane, :q, :schema).new(
            prefix: command.prefix, lane: nil, q: nil, schema: nil,
          )
          list = UseCases::Read::ListKeys.call(list_cmd, call, deps)
          return list if list.failure?

          leaves = list.value || []

          warnings = leaves.empty? ? ["no keys under #{command.prefix}"] : []
          steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }

          plan = Textus::Store::Retention::Plan.new(steps: steps, warnings: warnings)
          return success(plan) if command.dry_run

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
          success(plan)
        end

        private

        def deps
          Struct.new(:file_system, :manifest, :schemas, :audit_log, :layout, :writer, :reader).new(
            file_system, manifest, schemas, audit_log, layout, writer, reader
          )
        end
      end
    end
  end
end
