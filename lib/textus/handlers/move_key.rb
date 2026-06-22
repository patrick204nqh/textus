module Textus
  module Handlers
    class MoveKey
      def initialize(container:, manifest:)
        @container = container
        @manifest = manifest
      end

      def call(command, call)
        Textus::Manifest::Data.validate_key!(command.old_key)
        Textus::Manifest::Data.validate_key!(command.new_key)

        return Result.failure(:usage_error, "mv: old and new keys are identical") if command.old_key == command.new_key

        old_res = @manifest.resolver.resolve(command.old_key)
        new_res = @manifest.resolver.resolve(command.new_key)

        return Result.failure(:not_found, "source key '#{command.old_key}' not found") unless @container.pipeline.exists?(command.old_key)

        zone_check = validate_zone(old_res.entry, new_res.entry)
        return zone_check if zone_check

        if @container.pipeline.exists?(command.new_key)
          return Result.failure(:usage_error, "mv: target '#{command.new_key}' already exists at #{new_res.path}")
        end

        pre_env = @container.pipeline.read(command.old_key)
        unless pre_env.uid
          @container.pipeline.write(
            command.old_key, mentry: old_res.entry, call: call,
                             payload: Textus::Value::Payload.new(meta: pre_env.meta, body: pre_env.body, content: pre_env.content)
          )
        end

        if command.dry_run
          return Result.success({
                                  "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => true,
                                  "from_key" => command.old_key, "to_key" => command.new_key,
                                  "from_path" => old_res.path, "to_path" => new_res.path,
                                  "uid" => pre_env.uid
                                })
        end

        envelope = @container.pipeline.move(
          from_key: command.old_key, to_key: command.new_key,
          new_mentry: new_res.entry, call: call
        )

        Result.success({
                         "protocol" => Textus::PROTOCOL, "ok" => true,
                         "from_key" => command.old_key, "to_key" => command.new_key,
                         "from_path" => old_res.path, "to_path" => new_res.path,
                         "uid" => envelope.uid, "envelope" => envelope.to_h_for_wire
                       })
      end

      private

      def validate_zone(old_mentry, new_mentry)
        if old_mentry.lane != new_mentry.lane
          return Result.failure(:usage_error,
                                "mv: cross-zone refused (#{old_mentry.lane} -> #{new_mentry.lane}). Use put+delete.")
        end
        if old_mentry.format != new_mentry.format
          return Result.failure(:usage_error,
                                "mv: format mismatch (#{old_mentry.format} -> #{new_mentry.format}); refusing.")
        end
        nil
      end
    end
  end
end
