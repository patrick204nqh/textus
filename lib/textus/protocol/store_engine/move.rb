module Textus
  module Protocol
    class StoreEngine
      module Move
        MoveResult = Data.define(:from_key, :to_key, :from_path, :to_path, :dry_run, :envelope)

        module_function

        def call(from_key:, to_key:, deps:, if_etag: nil, dry_run: false)
          validate!(from_key, to_key)
          from_path, to_path, from_entry, to_entry = resolve_paths(from_key, to_key, deps)
          assert_source_exists!(from_key, from_path, deps)
          assert_target_not_exists!(to_path)
          check_cross_zone!(from_entry, to_entry)
          ensure_uid!(from_key, from_entry, from_path, deps)
          etag_before = Pipeline.check_etag(from_key, from_path, if_etag, deps.file_system)

          if dry_run
            return MoveResult.new(from_key:, to_key:, from_path:, to_path:,
                                  dry_run: true, envelope: nil)
          end

          deps.file_system.mv(from_path, to_path)
          Pipeline.prune_parents(from_path, deps)
          rewrite_basename!(to_key, to_path, to_entry)
          etag_after = Value::Etag.for_file(to_path)
          envelope = deps.reader.read(key: to_key)
          append_audit(to_key, etag_before, etag_after, deps)
          reindex_entry(from_key, to_key, to_entry, envelope, deps)
          Pipeline.emit_event(deps, event_type: "entry.moved",
                                    pending_key: from_key, emit_key: to_key,
                                    emit_lane: to_entry.lane,
                                    pending_keys: [from_key, to_key])
          MoveResult.new(from_key:, to_key:, from_path:, to_path:,
                         dry_run: false, envelope:)
        end

        def validate!(from_key, to_key)
          Manifest::Data.validate_key!(from_key)
          Manifest::Data.validate_key!(to_key)
          raise UsageError.new("old and new keys are identical") if from_key == to_key
        end

        def resolve_paths(from_key, to_key, deps)
          from = deps.manifest.resolver.resolve(from_key)
          to   = deps.manifest.resolver.resolve(to_key)
          [from.path, to.path, from.entry, to.entry]
        end

        def assert_source_exists!(key, path, deps)
          return if deps.file_system.exists?(path)

          raise UnknownKey.new(key, suggestions: deps.manifest.resolver.suggestions_for(key))
        end

        def assert_target_not_exists!(path)
          return unless path && File.exist?(path)

          raise UsageError.new("target already exists")
        end

        def check_cross_zone!(from_entry, to_entry)
          return if from_entry.lane == to_entry.lane

          raise UsageError.new("cross-zone moves forbidden (#{from_entry.lane} → #{to_entry.lane})")
        end

        def ensure_uid!(_key, entry, path, deps)
          return if Infra::Store::Envelope::Meta::NO_META_FORMATS.include?(entry.format)
          return unless path && deps.file_system.exists?(path)

          raw = deps.file_system.read(path)
          parsed = Format.for(entry.format).parse(raw, path:)
          meta = parsed["_meta"] || {}
          return if meta["uid"].is_a?(String) && !meta["uid"].empty?

          new_meta, = Infra::Store::Envelope::Meta.inject_all(meta, parsed["content"], {},
                                                              format: entry.format)
          bytes, = Format.for(entry.format).serialize_for_put(
            meta: new_meta, body: parsed["body"] || "", content: parsed["content"], path:,
          )
          deps.file_system.write(path, bytes)
        end

        def rewrite_basename!(key, path, entry)
          basename = key.split(".").last
          Format.for(entry.format).rewrite_name(path, basename)
        end

        def append_audit(key, etag_before, etag_after, deps)
          deps.audit_log.append(
            role: deps.call.role, verb: "key_mv", key:,
            etag_before:, etag_after:,
            correlation_id: deps.call.correlation_id
          )
        end

        def reindex_entry(from_key, to_key, to_entry, envelope, deps)
          deps.entry_index.remove(key: from_key)
          content = envelope.content ? envelope.content.to_json : envelope.body
          deps.entry_index.record(
            key: to_key, lane: to_entry.lane, format: to_entry.format,
            schema: to_entry.schema, content:
          )
        end
      end
    end
  end
end
