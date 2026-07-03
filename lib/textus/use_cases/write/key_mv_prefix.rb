module Textus
  module UseCases
    module Write
      class KeyMvPrefix < Base
        handles Dispatch::Contracts::KeyMvPrefix
        needs :file_system, :manifest, :schemas, :audit_log, :layout, :writer, :reader

        def call
          if command.from_prefix.nil? || command.to_prefix.nil?
            return failure(:usage_error,
                           "from_prefix and to_prefix required")
          end

          list_cmd = Data.define(:prefix, :lane, :q, :schema).new(
            prefix: command.from_prefix, lane: nil, q: nil, schema: nil,
          )
          list = UseCases::Read::ListKeys.call(list_cmd, call, deps)
          return list if list.failure?

          leaves = list.value || []

          if leaves.any? { |r| r["key"] == command.from_prefix }
            return failure(:usage_error,
                           "from_prefix '#{command.from_prefix}' is itself a leaf — use `mv` to rename a single key")
          end

          warnings = leaves.empty? ? ["no keys under #{command.from_prefix}"] : []
          steps = leaves.map do |row|
            old_key = row["key"]
            tail = old_key.delete_prefix("#{command.from_prefix}.")
            new_key = "#{command.to_prefix}.#{tail}"
            { "op" => "mv", "from" => old_key, "to" => new_key }
          end

          plan = Textus::Infra::Store::Retention::Plan.new(steps: steps, warnings: warnings)
          return success(plan) if command.dry_run

          steps.each do |step|
            move = MoveKey.call(
              Data.define(:old_key, :new_key, :if_etag, :dry_run).new(
                old_key: step["from"], new_key: step["to"], if_etag: nil, dry_run: false,
              ),
              call,
              deps,
            )
            return move if move.failure?
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
