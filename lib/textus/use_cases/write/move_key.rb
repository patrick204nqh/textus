module Textus
  module UseCases
    module Write
      module MoveKey
        HANDLES = Dispatch::Contracts::MvKey
        NEEDS = %i[file_store manifest schemas audit_log layout writer reader].freeze

        def self.call(command, call, deps)
          Textus::Manifest::Data.validate_key!(command.old_key)
          Textus::Manifest::Data.validate_key!(command.new_key)

          return Value::Result.failure(:usage_error, "mv: old and new keys are identical") if command.old_key == command.new_key

          old_res = deps.manifest.resolver.resolve(command.old_key)
          new_res = deps.manifest.resolver.resolve(command.new_key)

          reader = deps.reader

          unless reader.exists?(command.old_key)
            return Value::Result.failure(:not_found,
                                         "source key '#{command.old_key}' not found")
          end

          zone_check = validate_zone(old_res.entry, new_res.entry)
          return zone_check if zone_check

          if reader.exists?(command.new_key)
            return Value::Result.failure(:usage_error, "mv: target '#{command.new_key}' already exists at #{new_res.path}")
          end

          pre_env = reader.read(command.old_key)
          writer = deps.writer
          unless pre_env.uid
            writer.put(
              command.old_key, mentry: old_res.entry, call: call,
                               payload: Textus::Value::Payload.new(meta: pre_env.meta, body: pre_env.body, content: pre_env.content)
            )
          end

          if command.dry_run
            return Value::Result.success({
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

          Value::Result.success({
                                  "protocol" => Textus::PROTOCOL, "ok" => true,
                                  "from_key" => command.old_key, "to_key" => command.new_key,
                                  "from_path" => old_res.path, "to_path" => new_res.path,
                                  "uid" => envelope.uid, "envelope" => envelope.to_h_for_wire
                                })
        end

        def self.validate_zone(old_entry, new_entry)
          return nil if old_entry.lane == new_entry.lane

          Value::Result.failure(:usage_error,
                                "mv: cross-zone moves are forbidden (from #{old_entry.lane} to #{new_entry.lane})")
        end
        private_class_method :validate_zone
      end
    end
  end
end
