module Textus
  module Write
    class Mv
      def initialize(container:, call:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @events       = container.events
      end

      def call(old_key, new_key, dry_run: false)
        old_res, new_res = prepare(old_key, new_key)
        return dry_run_result(old_key, new_key, old_res, new_res) if dry_run

        ensure_uid!(old_key, old_res.entry)
        envelope = writer.move(
          from_key: old_key, to_key: new_key,
          new_mentry: new_res.entry
        )
        publish_renamed(old_key, new_key, envelope)
        success_result(old_key, new_key, old_res, new_res, envelope)
      end

      private

      def hook_context
        @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      end

      def prepare(old_key, new_key)
        Textus::Manifest::Data.validate_key!(old_key)
        Textus::Manifest::Data.validate_key!(new_key)
        raise UsageError.new("mv: old and new keys are identical") if old_key == new_key

        old_res = @manifest.resolver.resolve(old_key)
        new_res = @manifest.resolver.resolve(new_key)
        raise UnknownKey.new(old_key) unless reader.exists?(old_key)

        validate_zone_and_format!(old_res.entry, new_res.entry)
        guard_for(:mv, old_key).check!(eval_for(:mv, target_key: old_key))
        guard_for(:mv, new_key).check!(eval_for(:mv, target_key: new_key))
        raise UsageError.new("mv: target '#{new_key}' already exists at #{new_res.path}") if reader.exists?(new_key)

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

      # If the source file lacks a UID, rewrite it in-place via the writer
      # so a UID gets injected before the move. This produces one "put"
      # audit row, then the "mv" row from Writer#move.
      def ensure_uid!(old_key, old_mentry)
        pre_env = reader.read(old_key)
        return if pre_env.uid

        writer.put(
          old_key, mentry: old_mentry,
                   payload: Textus::Envelope::IO::Writer::Payload.new(
                     meta: pre_env.meta, body: pre_env.body, content: pre_env.content,
                   )
        )
      end

      def publish_renamed(old_key, new_key, envelope)
        @events.publish(:entry_renamed,
                        ctx: hook_context,
                        key: new_key,
                        from_key: old_key,
                        to_key: new_key,
                        envelope: envelope)
      end

      def dry_run_result(old_key, new_key, old_res, new_res)
        pre_env = reader.read(old_key)
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

      def guard_for(transition, key, if_etag: nil)
        Textus::Domain::Policy::GuardFactory.new(
          manifest: @manifest, schemas: @container.schemas, extra: { if_etag: if_etag },
        ).for(transition, key)
      end

      def eval_for(transition, target_key:, envelope: nil)
        Textus::Domain::Policy::Evaluation.new(
          actor: @call.role, transition: transition, origin: nil,
          target: target_key, envelope: envelope, snapshot: @manifest
        )
      end

      def writer
        @writer ||= Textus::Envelope::IO::Writer.from(container: @container, call: @call)
      end

      def reader
        @reader ||= Textus::Envelope::IO::Reader.from(container: @container)
      end
    end
  end
end
