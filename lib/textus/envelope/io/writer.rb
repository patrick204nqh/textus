require "fileutils"

module Textus
  class Envelope
    module IO
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

        def initialize(file_store:, manifest:, schemas:, audit_log:, ctx:, reader:)
          @file_store = file_store
          @manifest   = manifest
          @schemas    = schemas
          @audit_log  = audit_log
          @ctx        = ctx
          @reader     = reader
        end

        def put(key, mentry:, payload:, if_etag: nil)
          path = @manifest.resolver.resolve(key).path

          meta = payload.meta || {}

          existing_uid = @reader.existing_uid(key)
          meta, content = ensure_uid(mentry.format, meta, payload.content, existing_uid)

          bytes, eff_meta, eff_body, eff_content = serialize_for_put(
            mentry: mentry, path: path,
            meta: meta, body: payload.body, content: content
          )

          enforce_name_match!(path, eff_meta, mentry.format)

          schema = @schemas.fetch_or_nil(mentry.schema)
          if schema
            Entry.for_format(mentry.format).validate_against(
              schema,
              { "_meta" => eff_meta, "content" => eff_content },
            )
          end

          etag_before = @file_store.exists?(path) ? @file_store.etag(path) : nil
          raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && (etag_before != if_etag)

          @file_store.write(path, bytes)
          etag_after = Etag.for_bytes(bytes)
          envelope = Textus::Envelope.build(
            key: key, mentry: mentry, path: path,
            meta: eff_meta, body: eff_body, etag: etag_after, content: eff_content
          )
          @audit_log.append(
            role: @ctx.role, verb: "put", key: key,
            etag_before: etag_before, etag_after: etag_after,
            extras: @ctx.correlation_id ? { "correlation_id" => @ctx.correlation_id } : nil
          )
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
          @audit_log.append(
            role: @ctx.role, verb: "delete", key: key,
            etag_before: etag_before, etag_after: nil,
            extras: @ctx.correlation_id ? { "correlation_id" => @ctx.correlation_id } : nil
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
          basename = to_key.split(".").last
          Entry.for_format(new_mentry.format).rewrite_name(to_path, basename)
          etag_after = Etag.for_file(to_path)

          raw = @file_store.read(to_path)
          parsed = Entry.for_format(new_mentry.format).parse(raw, path: to_path)
          envelope = Textus::Envelope.build(
            key: to_key, mentry: new_mentry, path: to_path,
            meta: parsed["_meta"], body: parsed["body"],
            etag: etag_after, content: parsed["content"]
          )

          extras = {
            "from_key" => from_key, "to_key" => to_key,
            "from_path" => from_path, "to_path" => to_path,
            "uid" => envelope.uid
          }
          extras["correlation_id"] = @ctx.correlation_id if @ctx.correlation_id

          @audit_log.append(
            role: @ctx.role, verb: "mv", key: to_key,
            etag_before: etag_before, etag_after: etag_after,
            extras: extras
          )

          envelope
        end

        private

        def ensure_uid(format, meta, content, existing_uid)
          Textus::Entry.for_format(format).inject_uid(meta, content, existing_uid)
        end

        def enforce_name_match!(path, meta, format)
          Textus::Entry.for_format(format).enforce_name_match!(path, meta)
        end

        def serialize_for_put(mentry:, path:, meta:, body:, content:)
          Textus::Entry.for_format(mentry.format).serialize_for_put(
            meta: meta, body: body, content: content, path: path,
          )
        end
      end
    end
  end
end
