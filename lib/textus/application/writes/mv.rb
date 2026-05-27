module Textus
  module Application
    module Writes
      class Mv
        # rubocop:disable Metrics/ParameterLists
        def initialize(ctx:, manifest:, file_store:, envelope_io:, bus:, authorizer:, store:)
          @ctx         = ctx
          @manifest    = manifest
          @file_store  = file_store
          @envelope_io = envelope_io
          @bus         = bus
          @authorizer  = authorizer
          @store       = store
        end
        # rubocop:enable Metrics/ParameterLists

        def call(old_key, new_key, dry_run: false)
          old_res, new_res = prepare(old_key, new_key)
          return dry_run_result(old_key, new_key, old_res, new_res) if dry_run

          ensure_uid!(old_key, old_res.entry)
          envelope = @envelope_io.move(
            from_key: old_key, to_key: new_key,
            old_mentry: old_res.entry, new_mentry: new_res.entry
          )
          publish_renamed(old_key, new_key, envelope)
          success_result(old_key, new_key, old_res, new_res, envelope)
        end

        private

        def reader
          @reader ||= Textus::Application::Reads::Get.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
          )
        end

        def prepare(old_key, new_key)
          @manifest.validate_key!(old_key)
          @manifest.validate_key!(new_key)
          raise UsageError.new("mv: old and new keys are identical") if old_key == new_key

          old_res = @manifest.resolve(old_key)
          new_res = @manifest.resolve(new_key)
          raise UnknownKey.new(old_key) unless @envelope_io.exists?(old_res.path)

          validate_zone_and_format!(old_res.entry, new_res.entry)
          @authorizer.authorize_write!(old_res.entry, role: @ctx.role)
          @authorizer.authorize_write!(new_res.entry, role: @ctx.role)
          raise UsageError.new("mv: target '#{new_key}' already exists at #{new_res.path}") if @envelope_io.exists?(new_res.path)

          [old_res, new_res]
        end

        def validate_zone_and_format!(old_mentry, new_mentry)
          if old_mentry.zone != new_mentry.zone
            raise UsageError.new(
              "mv: cross-zone move refused (#{old_mentry.zone} → #{new_mentry.zone}). " \
              "Use put+delete for cross-zone moves.",
            )
          end
          return if old_mentry.format == new_mentry.format

          raise UsageError.new("mv: format mismatch (#{old_mentry.format} → #{new_mentry.format}); refusing.")
        end

        # If the source file lacks a UID, rewrite it in-place via EnvelopeIO#write
        # so a UID gets injected before the move. This replaces the previous
        # Put(suppress_events: true) bypass with a direct EnvelopeIO call —
        # producing one "put" audit row, then the "mv" row from EnvelopeIO#move.
        def ensure_uid!(old_key, old_mentry)
          pre_env = reader.call(old_key)
          return if pre_env.uid

          @envelope_io.write(
            old_key, mentry: old_mentry,
                     payload: EnvelopeIO::Payload.new(
                       meta: pre_env.meta, body: pre_env.body, content: pre_env.content,
                     )
          )
        end

        def publish_renamed(old_key, new_key, envelope)
          @bus.publish(:entry_renamed,
                       store: @store,
                       role: @ctx.role,
                       key: new_key,
                       from_key: old_key,
                       to_key: new_key,
                       envelope: envelope,
                       correlation_id: @ctx.correlation_id)
        end

        def dry_run_result(old_key, new_key, old_res, new_res)
          pre_env = reader.call(old_key)
          {
            "protocol" => PROTOCOL, "ok" => true, "dry_run" => true,
            "from_key" => old_key, "to_key" => new_key,
            "from_path" => old_res.path, "to_path" => new_res.path,
            "uid" => pre_env.uid
          }
        end

        def success_result(old_key, new_key, old_res, new_res, envelope)
          {
            "protocol" => PROTOCOL, "ok" => true,
            "from_key" => old_key, "to_key" => new_key,
            "from_path" => old_res.path, "to_path" => new_res.path,
            "uid" => envelope.uid,
            "envelope" => envelope.to_h_for_wire
          }
        end
      end
    end
  end
end
