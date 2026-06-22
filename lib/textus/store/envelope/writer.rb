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
        def self.from(container:, call:)
          new(
            file_store: container.file_store, manifest: container.manifest,
            schemas: container.schemas, audit_log: container.audit_log,
            call: call, reader: Reader.from(container: container),
            geometry: container.geometry
          )
        end

        def initialize(file_store:, manifest:, schemas:, audit_log:, call:, reader:, geometry:) # rubocop:disable Metrics/ParameterLists
          @file_store = file_store
          @manifest   = manifest
          @schemas    = schemas
          @audit_log  = audit_log
          @call       = call
          @reader     = reader
          @geometry   = geometry
        end

        def put(key, mentry:, payload:, if_etag: nil)
          path  = resolve_path(key)
          meta  = payload.meta || {}
          content = payload.content

          existing_env   = read_existing(key)
          existing_meta  = existing_env ? existing_env.meta : {}
          meta, content  = inject_meta(meta, content, existing_meta, mentry.format)

          bytes, eff_meta, eff_body, eff_content = serialize_entry(mentry, path, meta, payload, content)

          enforce_name_match!(path, eff_meta, mentry.format)
          validate_schema(mentry, eff_meta, eff_content)
          validate_raw(eff_meta, eff_content, mentry.lane, mentry.format)

          etag_before = check_etag!(path, key, if_etag)
          write_bytes(path, bytes)

          envelope = build_envelope(key, mentry, path, eff_meta, eff_body, eff_content, bytes)
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

          envelope = @reader.read(to_key)

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
          floor = @geometry.lane_floor(path)
          return unless floor

          dir = File.dirname(path)
          while dir.start_with?("#{floor}/") && Dir.empty?(dir)
            Dir.rmdir(dir)
            dir = File.dirname(dir)
          end
        rescue SystemCallError
          nil
        end

        def read_existing(key)
          @reader.read(key)
        end

        def inject_meta(meta, content, existing_meta, format)
          Meta.inject_all(meta, content, existing_meta, format: format)
        end

        def resolve_path(key)
          @manifest.resolver.resolve(key).path
        end

        def serialize_entry(mentry, path, meta, payload, content)
          Textus::Format.for(mentry.format).serialize_for_put(
            meta: meta, body: payload.body, content: content, path: path,
          )
        end

        def enforce_name_match!(path, meta, format)
          Textus::Format.for(format).enforce_name_match!(path, meta)
        end

        def validate_schema(mentry, eff_meta, eff_content)
          schema = @schemas.fetch_or_nil(mentry.schema)
          return unless schema

          Format.for(mentry.format).validate_against(
            schema,
            { "_meta" => eff_meta, "content" => eff_content },
          )
        end

        def validate_raw(eff_meta, eff_content, lane, format)
          Textus::Format.for(format).validate_raw_entry!(
            { "_meta" => eff_meta, "content" => eff_content },
            lane,
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

        def build_envelope(key, mentry, path, eff_meta, eff_body, eff_content, bytes = nil) # rubocop:disable Metrics/ParameterLists
          raw = bytes || @file_store.read(path)
          Textus::Value::Envelope.build(
            key: key, mentry: mentry, path: path,
            meta: eff_meta, body: eff_body,
            etag: Value::Etag.for_bytes(raw),
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
