require "fileutils"

module Textus
  class Store
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    class Mover
      def initialize(store:, reader:, writer:, manifest:, audit_log:)
        @store = store
        @reader = reader
        @writer = writer
        @manifest = manifest
        @audit_log = audit_log
      end

      def call(old_key, new_key, as: Role::DEFAULT, dry_run: false, correlation_id: nil)
        @manifest.validate_key!(old_key)
        @manifest.validate_key!(new_key)
        raise UsageError.new("mv: old and new keys are identical") if old_key == new_key

        old_mentry, old_path, = @manifest.resolve(old_key)
        raise UnknownKey.new(old_key) unless File.exist?(old_path)

        new_mentry, new_path, = @manifest.resolve(new_key)

        if old_mentry.zone != new_mentry.zone
          raise UsageError.new(
            "mv: cross-zone move refused (#{old_mentry.zone} → #{new_mentry.zone}). " \
            "Use put+delete for cross-zone moves.",
          )
        end
        if old_mentry.format != new_mentry.format
          raise UsageError.new(
            "mv: format mismatch (#{old_mentry.format} → #{new_mentry.format}); refusing.",
          )
        end

        writers = @manifest.zone_writers(old_mentry.zone)
        raise WriteForbidden.new(old_key, old_mentry.zone, writers: writers) unless writers.include?(as)

        raise UsageError.new("mv: target '#{new_key}' already exists at #{new_path}") if File.exist?(new_path)

        # Mint uid before the move so the audit row carries it.
        pre_env = @reader.get(old_key)
        current_uid = pre_env["uid"]
        etag_before = pre_env["etag"]

        if dry_run
          return {
            "protocol" => PROTOCOL, "ok" => true, "dry_run" => true,
            "from_key" => old_key, "to_key" => new_key,
            "from_path" => old_path, "to_path" => new_path,
            "uid" => current_uid
          }
        end

        if current_uid.nil?
          # Write the uid in place first so the source file carries it before mv.
          pre_env = @writer.put(old_key,
                                meta: pre_env["_meta"],
                                body: pre_env["body"],
                                content: pre_env["content"],
                                as: as,
                                suppress_events: true)
          current_uid = pre_env["uid"]
          etag_before = pre_env["etag"]
        end

        FileUtils.mkdir_p(File.dirname(new_path))
        FileUtils.mv(old_path, new_path)
        rewrite_name_for_mv!(new_mentry, new_path, new_key)
        etag_after = Etag.for_file(new_path)

        extras = {
          "from_key" => old_key, "to_key" => new_key,
          "from_path" => old_path, "to_path" => new_path,
          "uid" => current_uid
        }
        extras["correlation_id"] = correlation_id if correlation_id

        @audit_log.append(
          role: as, verb: "mv", key: new_key,
          etag_before: etag_before, etag_after: etag_after,
          extras: extras
        )

        new_envelope = @reader.get(new_key)
        @store.fire_event(:mv, key: new_key, from_key: old_key, to_key: new_key, envelope: new_envelope)
        {
          "protocol" => PROTOCOL, "ok" => true,
          "from_key" => old_key, "to_key" => new_key,
          "from_path" => old_path, "to_path" => new_path,
          "uid" => current_uid,
          "envelope" => new_envelope
        }
      end

      private

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
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
