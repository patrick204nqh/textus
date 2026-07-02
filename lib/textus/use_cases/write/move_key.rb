module Textus
  module UseCases
    module Write
      class MoveKey < Base
        handles Dispatch::Contracts::MvKey
        needs :file_system, :manifest, :schemas, :audit_log, :layout, :writer, :reader

        def call
          Textus::Manifest::Data.validate_key!(command.old_key)
          Textus::Manifest::Data.validate_key!(command.new_key)

          return failure(:usage_error, "mv: old and new keys are identical") if command.old_key == command.new_key

          old_res = manifest.resolver.resolve(command.old_key)
          new_res = manifest.resolver.resolve(command.new_key)

          unless reader.exists?(command.old_key)
            return failure(:not_found,
                           "source key '#{command.old_key}' not found")
          end

          zone_check = validate_zone(old_res.entry, new_res.entry)
          return zone_check if zone_check

          if reader.exists?(command.new_key)
            return failure(:usage_error, "mv: target '#{command.new_key}' already exists at #{new_res.path}")
          end

          pre_env = reader.read(command.old_key)
          unless pre_env.uid
            writer.put(
              command.old_key, mentry: old_res.entry, call: call,
                               payload: Textus::Value::Payload.new(meta: pre_env.meta, body: pre_env.body, content: pre_env.content)
            )
          end

          if command.dry_run
            return success({
                             "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => true,
                             "from_key" => command.old_key, "to_key" => command.new_key,
                             "from_path" => old_res.path, "to_path" => new_res.path,
                             "uid" => pre_env.uid
                           })
          end

          envelope = writer.move(
            from_key: command.old_key, to_key: command.new_key,
            new_mentry: new_res.entry, call: call
          )

          success({
                    "protocol" => Textus::PROTOCOL, "ok" => true,
                    "from_key" => command.old_key, "to_key" => command.new_key,
                    "from_path" => old_res.path, "to_path" => new_res.path,
                    "uid" => envelope.uid, "envelope" => envelope.to_h_for_wire
                  })
        end

        private

        def validate_zone(old_entry, new_entry)
          return nil if old_entry.lane == new_entry.lane

          failure(:usage_error,
                  "mv: cross-zone moves are forbidden (from #{old_entry.lane} to #{new_entry.lane})")
        end
      end
    end
  end
end
