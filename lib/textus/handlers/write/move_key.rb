module Textus
  module Handlers
    module Write
      module MoveKey
        HANDLES = Dispatch::Contracts::MoveKey
        NEEDS   = %i[file_store manifest schemas audit_log reader layout].freeze

        def self.call(command, call, deps)
          Textus::Manifest::Data.validate_key!(command.old_key)
          Textus::Manifest::Data.validate_key!(command.new_key)

          return Value::Result.failure(:usage_error, "mv: old and new keys are identical") if command.old_key == command.new_key

          old_res = deps.manifest.resolver.resolve(command.old_key)
          new_res = deps.manifest.resolver.resolve(command.new_key)

          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)

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
          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          unless pre_env.uid
            writer.put(
              command.old_key, mentry: old_res.entry,
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
            new_mentry: new_res.entry
          )

          Value::Result.success({
                                  "protocol" => Textus::PROTOCOL, "ok" => true,
                                  "from_key" => command.old_key, "to_key" => command.new_key,
                                  "from_path" => old_res.path, "to_path" => new_res.path,
                                  "uid" => envelope.uid, "envelope" => envelope.to_h_for_wire
                                })
        end

        def self.validate_zone(old_mentry, new_mentry)
          if old_mentry.lane != new_mentry.lane
            return Value::Result.failure(:usage_error,
                                         "mv: cross-zone refused (#{old_mentry.lane} -> #{new_mentry.lane}). Use put+delete.")
          end
          if old_mentry.format != new_mentry.format
            return Value::Result.failure(:usage_error,
                                         "mv: format mismatch (#{old_mentry.format} -> #{new_mentry.format}); refusing.")
          end
          nil
        end
      end
    end
  end
end
