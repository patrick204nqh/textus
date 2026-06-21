# frozen_string_literal: true

module Textus
  module Action
    class KeyMv < Base

      verb :key_mv
      summary "Rename one entry (same zone + format). Refuses if the target exists. Single-key, lower blast radius than key_mv_prefix."
      surfaces :cli, :mcp
      cli "key mv"
      arg :old_key, String, required: true, positional: true,
                            description: "current dotted key"
      arg :new_key, String, required: true, positional: true,
                            description: "new dotted key (must be the same zone and format as old_key)"
      arg :dry_run, :boolean,
          description: "when true, returns the planned move (from/to paths, uid) without applying it; " \
                       "defaults to false, so omitting it applies the move immediately " \
                       "(unlike the bulk key_mv_prefix, which defaults to a dry-run plan)"

      def self.call(container:, call:, old_key:, new_key:, dry_run: false)
        execute_move(container: container, call: call, old_key: old_key, new_key: new_key, dry_run: dry_run)
      end

      def self.execute_move(container:, call:, old_key:, new_key:, dry_run:)
        old_res, new_res = prepare(container: container, old_key: old_key, new_key: new_key)
        return dry_run_result(container: container, old_key: old_key, new_key: new_key, old_res: old_res, new_res: new_res) if dry_run

        envelope = apply_move(container: container, call: call, old_key: old_key, new_key: new_key, old_res: old_res, new_res: new_res)
        success_result(old_key: old_key, new_key: new_key, old_res: old_res, new_res: new_res, envelope: envelope)
      end

      def self.apply_move(container:, call:, old_key:, new_key:, old_res:, new_res:)
        ensure_uid!(container: container, call: call, old_key: old_key, old_mentry: old_res.entry)
        container.compositor.move(
          from_key: old_key,
          to_key: new_key,
          new_mentry: new_res.entry,
          call: call,
        )
      end

      def self.success_result(old_key:, new_key:, old_res:, new_res:, envelope:)
        {
          "protocol" => Textus::PROTOCOL,
          "ok" => true,
          "from_key" => old_key,
          "to_key" => new_key,
          "from_path" => old_res.path,
          "to_path" => new_res.path,
          "uid" => envelope.uid,
          "envelope" => envelope.to_h_for_wire,
        }
      end

      def self.prepare(container:, old_key:, new_key:)
        Textus::Manifest::Data.validate_key!(old_key)
        Textus::Manifest::Data.validate_key!(new_key)
        raise UsageError.new("mv: old and new keys are identical") if old_key == new_key

        old_res = container.manifest.resolver.resolve(old_key)
        new_res = container.manifest.resolver.resolve(new_key)
        raise UnknownKey.new(old_key) unless container.compositor.exists?(old_key)

        validate_zone_and_format!(old_mentry: old_res.entry, new_mentry: new_res.entry)
        raise UsageError.new("mv: target '#{new_key}' already exists at #{new_res.path}") if container.compositor.exists?(new_key)

        [old_res, new_res]
      end

      def self.validate_zone_and_format!(old_mentry:, new_mentry:)
        if old_mentry.lane != new_mentry.lane
          raise UsageError.new(
            "mv: cross-zone move refused (#{old_mentry.lane} -> #{new_mentry.lane}). " \
            "Use put+delete for cross-zone moves.",
          )
        end
        return if old_mentry.format == new_mentry.format

        raise UsageError.new("mv: format mismatch (#{old_mentry.format} -> #{new_mentry.format}); refusing.")
      end

      def self.ensure_uid!(container:, call:, old_key:, old_mentry:)
        pre_env = container.compositor.read(old_key)
        return if pre_env.uid

        container.compositor.write(
          old_key,
          mentry: old_mentry,
          payload: Textus::Store::Envelope::Writer::Payload.new(
            meta: pre_env.meta,
            body: pre_env.body,
            content: pre_env.content,
          ),
          call: call,
        )
      end

      def self.dry_run_result(container:, old_key:, new_key:, old_res:, new_res:)
        pre_env = container.compositor.read(old_key)
        {
          "protocol" => Textus::PROTOCOL,
          "ok" => true,
          "dry_run" => true,
          "from_key" => old_key,
          "to_key" => new_key,
          "from_path" => old_res.path,
          "to_path" => new_res.path,
          "uid" => pre_env.uid,
        }
      end
    end
  end
end
