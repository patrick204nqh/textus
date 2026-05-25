require "fileutils"

module Textus
  class Store
    class Mover
      MovePlan = Data.define(
        :old_key, :new_key, :old_path, :new_path,
        :new_mentry, :uid, :etag_before, :as
      )

      def initialize(store:, reader:, writer:, manifest:, audit_log:)
        @store = store
        @reader = reader
        @writer = writer
        @manifest = manifest
        @audit_log = audit_log
      end

      def call(old_key, new_key, as: Role::DEFAULT, dry_run: false, correlation_id: nil)
        plan, pre_env = prepare_plan(old_key, new_key, as: as)
        return dry_run_result(plan) if dry_run

        plan = ensure_uid!(plan, pre_env: pre_env)
        etag_after = perform_move!(plan)
        new_envelope = record_move(plan, etag_after: etag_after, correlation_id: correlation_id)
        success_result(plan, new_envelope: new_envelope)
      end

      private

      # Validates inputs, resolves manifest entries, and reads the source
      # envelope. Returns [MovePlan, pre_envelope]; the pre_envelope is only
      # needed by ensure_uid! and is threaded separately to keep MovePlan
      # focused on the planned operation.
      def prepare_plan(old_key, new_key, as:)
        @manifest.validate_key!(old_key)
        @manifest.validate_key!(new_key)
        raise UsageError.new("mv: old and new keys are identical") if old_key == new_key

        old_mentry, old_path, = @manifest.resolve(old_key)
        raise UnknownKey.new(old_key) unless File.exist?(old_path)

        new_mentry, new_path, = @manifest.resolve(new_key)
        validate_zone_and_format!(old_mentry, new_mentry)
        validate_writer!(old_mentry, old_key, as)
        raise UsageError.new("mv: target '#{new_key}' already exists at #{new_path}") if File.exist?(new_path)

        pre_env = @reader.get(old_key)
        plan = MovePlan.new(
          old_key: old_key, new_key: new_key,
          old_path: old_path, new_path: new_path,
          new_mentry: new_mentry,
          uid: pre_env["uid"], etag_before: pre_env["etag"], as: as
        )
        [plan, pre_env]
      end

      def validate_zone_and_format!(old_mentry, new_mentry)
        if old_mentry.zone != new_mentry.zone
          raise UsageError.new(
            "mv: cross-zone move refused (#{old_mentry.zone} → #{new_mentry.zone}). " \
            "Use put+delete for cross-zone moves.",
          )
        end
        return if old_mentry.format == new_mentry.format

        raise UsageError.new(
          "mv: format mismatch (#{old_mentry.format} → #{new_mentry.format}); refusing.",
        )
      end

      def validate_writer!(mentry, key, as)
        writers = @manifest.zone_writers(mentry.zone)
        return if writers.include?(as)

        raise WriteForbidden.new(key, mentry.zone, writers: writers)
      end

      def ensure_uid!(plan, pre_env:)
        return plan if plan.uid

        env = @writer.put(
          plan.old_key,
          meta: pre_env["_meta"],
          body: pre_env["body"],
          content: pre_env["content"],
          as: plan.as,
          suppress_events: true,
        )
        plan.with(uid: env["uid"], etag_before: env["etag"])
      end

      def perform_move!(plan)
        FileUtils.mkdir_p(File.dirname(plan.new_path))
        FileUtils.mv(plan.old_path, plan.new_path)
        rewrite_name_for_mv!(plan.new_mentry, plan.new_path, plan.new_key)
        Etag.for_file(plan.new_path)
      end

      def record_move(plan, etag_after:, correlation_id:)
        extras = {
          "from_key" => plan.old_key, "to_key" => plan.new_key,
          "from_path" => plan.old_path, "to_path" => plan.new_path,
          "uid" => plan.uid
        }
        extras["correlation_id"] = correlation_id if correlation_id

        @audit_log.append(
          role: plan.as, verb: "mv", key: plan.new_key,
          etag_before: plan.etag_before, etag_after: etag_after,
          extras: extras
        )
        new_envelope = @reader.get(plan.new_key)
        @store.fire_event(
          :entry_renamed,
          key: plan.new_key, from_key: plan.old_key, to_key: plan.new_key,
          envelope: new_envelope
        )
        new_envelope
      end

      def dry_run_result(plan)
        {
          "protocol" => PROTOCOL, "ok" => true, "dry_run" => true,
          "from_key" => plan.old_key, "to_key" => plan.new_key,
          "from_path" => plan.old_path, "to_path" => plan.new_path,
          "uid" => plan.uid
        }
      end

      def success_result(plan, new_envelope:)
        {
          "protocol" => PROTOCOL, "ok" => true,
          "from_key" => plan.old_key, "to_key" => plan.new_key,
          "from_path" => plan.old_path, "to_path" => plan.new_path,
          "uid" => plan.uid,
          "envelope" => new_envelope
        }
      end

      # If the moved file carries a `name:` field (markdown) or `_meta.name`
      # (json/yaml), rewrite it to the new basename so enforce_name_match! stays
      # happy on the next read. Only touches the bytes when name actually changes.
      def rewrite_name_for_mv!(mentry, new_path, new_key)
        strategy = Entry.for_format(mentry.format)
        raw = File.binread(new_path)
        parsed = strategy.parse(raw, path: new_path)
        basename = new_key.split(".").last

        case mentry.format
        when "markdown"
          meta = parsed["_meta"] || {}
          return unless meta.is_a?(Hash) && meta["name"].is_a?(String) && meta["name"] != basename

          meta = meta.merge("name" => basename)
          File.binwrite(new_path, strategy.serialize(meta: meta, body: parsed["body"]))
        when "json", "yaml"
          meta = parsed["_meta"]
          return unless meta.is_a?(Hash) && meta["name"].is_a?(String) && meta["name"] != basename

          new_meta = meta.merge("name" => basename)
          File.binwrite(new_path, strategy.serialize(meta: new_meta, body: "", content: parsed["content"]))
        end
      end
    end
  end
end
