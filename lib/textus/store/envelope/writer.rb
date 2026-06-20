require "fileutils"

module Textus
  class Store
    module Envelope
      # Owns the write pipeline (validate, serialize, etag-check, write, audit).
      # Talks to ports (FileStore, Schemas, AuditLog, Manifest) and an
      # Reader for the existing-uid lookup.
      #
      # Invariant: every public method's final action is @audit_log.append(...).
      #
      # No permission check, no event firing — those belong to the caller
      # (Write::Put / ::Delete / ::Mv).
      class Writer
        Payload = Data.define(:meta, :body, :content)

        def self.from(container:, call:)
          new(
            file_store: container.file_store, manifest: container.manifest,
            schemas: container.schemas, audit_log: container.audit_log,
            call: call, reader: Reader.from(container: container)
          )
        end

        def initialize(file_store:, manifest:, schemas:, audit_log:, call:, reader:)
          @file_store = file_store
          @manifest   = manifest
          @schemas    = schemas
          @audit_log  = audit_log
          @call       = call
          @reader     = reader
        end

        def put(key, mentry:, payload:, if_etag: nil)
          path = resolve_path(key)
          meta, content = prepare_uid(mentry, payload, key)
          bytes, eff_meta, eff_body, eff_content = serialize_entry(mentry, path, meta, payload, content)
          enforce_name_match!(path, eff_meta, mentry.format)
          validate_schema(mentry, eff_meta, eff_content)
          etag_before = check_etag!(path, key, if_etag)
          write_bytes(path, bytes)
          envelope = build_envelope(key, mentry, path, eff_meta, eff_body, eff_content)
          audit_put(key, etag_before, envelope.etag)
          envelope
        end

        def delete(key, mentry: nil, if_etag: nil) # rubocop:disable Lint/UnusedMethodArgument
          # `mentry:` is accepted for symmetry with `put` / `move` and to
          # leave room for future format-specific delete hooks; no field
          # on it is needed today.
          path = @manifest.resolver.resolve(key).path
          raise UnknownKey.new(key, suggestions: @manifest.resolver.suggestions_for(key)) unless @file_store.exists?(path)

          etag_before = @file_store.etag(path)
          raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

          @file_store.delete(path)
          prune_empty_parents(path)
          @audit_log.append(
            role: @call.role, verb: "key_delete", key: key,
            etag_before: etag_before, etag_after: nil,
            extras: @call.correlation_id ? { "correlation_id" => @call.correlation_id } : nil
          )
        end

        def move(from_key:, to_key:, new_mentry:, if_etag: nil)
          from_path = @manifest.resolver.resolve(from_key).path
          to_path   = @manifest.resolver.resolve(to_key).path
          raise UnknownKey.new(from_key, suggestions: @manifest.resolver.suggestions_for(from_key)) unless @file_store.exists?(from_path)

          etag_before = @file_store.etag(from_path)
          raise EtagMismatch.new(from_key, if_etag, etag_before) if if_etag && if_etag != etag_before

          FileUtils.mkdir_p(File.dirname(to_path))
          FileUtils.mv(from_path, to_path)
          prune_empty_parents(from_path)
          basename = to_key.split(".").last
          Format.for(new_mentry.format).rewrite_name(to_path, basename)
          etag_after = Value::Etag.for_file(to_path)

          raw = @file_store.read(to_path)
          parsed = Format.for(new_mentry.format).parse(raw, path: to_path)
          envelope = Textus::Value::Envelope.build(
            key: to_key, mentry: new_mentry, path: to_path,
            meta: parsed["_meta"], body: parsed["body"],
            etag: etag_after, content: parsed["content"]
          )

          extras = {
            "from_key" => from_key, "to_key" => to_key,
            "from_path" => from_path, "to_path" => to_path,
            "uid" => envelope.uid
          }
          extras["correlation_id"] = @call.correlation_id if @call.correlation_id

          @audit_log.append(
            role: @call.role, verb: "key_mv", key: to_key,
            etag_before: etag_before, etag_after: etag_after,
            extras: extras
          )

          envelope
        end

        private

        # After a file leaves a directory (delete or move-source), remove any
        # now-empty parent dirs so bulk move/delete doesn't accrue orphan dirs
        # (F3 of #161). Floored at the entry's *zone directory* — a zone is a
        # declared, first-class container, so its own dir is preserved even when
        # momentarily empty; only the sub-dirs the bulk op carved out are
        # pruned. Stops at the first non-empty ancestor, so a dir holding a
        # `.gitkeep` or sibling entries survives. Best-effort: a lost race or a
        # non-empty dir is silently fine, never fatal to the write.
        def prune_empty_parents(path)
          floor = zone_floor(path)
          return unless floor

          dir = File.dirname(path)
          while dir.start_with?("#{floor}/") && Dir.empty?(dir)
            Dir.rmdir(dir)
            dir = File.dirname(dir)
          end
        rescue SystemCallError
          nil
        end

        # The zone directory under which `path` lives (`<root>/zones/<zone>`),
        # or nil if `path` is not under the store's zones tree.
        def zone_floor(path)
          zones_root = File.join(@manifest.data.root, "data")
          prefix = "#{zones_root}/"
          return nil unless path.start_with?(prefix)

          zone_seg = path.delete_prefix(prefix).split("/").first
          zone_seg && File.join(zones_root, zone_seg)
        end

        def ensure_uid(format, meta, content, existing_uid)
          Textus::Format.for(format).inject_uid(meta, content, existing_uid)
        end

        def enforce_name_match!(path, meta, format)
          Textus::Format.for(format).enforce_name_match!(path, meta)
        end

        def serialize_for_put(mentry:, path:, meta:, body:, content:)
          Textus::Format.for(mentry.format).serialize_for_put(
            meta: meta, body: body, content: content, path: path,
          )
        end

        def resolve_path(key)
          @manifest.resolver.resolve(key).path
        end

        def prepare_uid(mentry, payload, key)
          meta = payload.meta || {}
          existing_uid = @reader.existing_uid(key)
          ensure_uid(mentry.format, meta, payload.content, existing_uid)
        end

        def serialize_entry(mentry, path, meta, payload, content)
          serialize_for_put(
            mentry: mentry, path: path,
            meta: meta, body: payload.body, content: content
          )
        end

        def validate_schema(mentry, eff_meta, eff_content)
          schema = @schemas.fetch_or_nil(mentry.schema)
          return unless schema

          Format.for(mentry.format).validate_against(
            schema,
            { "_meta" => eff_meta, "content" => eff_content },
          )
        end

        def check_etag!(path, key, if_etag)
          etag_before = @file_store.exists?(path) ? @file_store.etag(path) : nil
          raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && (etag_before != if_etag)

          etag_before
        end

        def write_bytes(path, bytes)
          @file_store.write(path, bytes)
        end

        def build_envelope(key, mentry, path, eff_meta, eff_body, eff_content)
          Textus::Value::Envelope.build(
            key: key, mentry: mentry, path: path,
            meta: eff_meta, body: eff_body,
            etag: Value::Etag.for_bytes(@file_store.read(path)),
            content: eff_content
          )
        end

        def audit_put(key, etag_before, etag_after)
          extras = @call.correlation_id ? { "correlation_id" => @call.correlation_id } : nil
          @audit_log.append(
            role: @call.role, verb: "put", key: key,
            etag_before: etag_before, etag_after: etag_after,
            extras: extras
          )
        end
      end
    end
  end
end
