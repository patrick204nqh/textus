module Textus
  module Application
    module Writes
      # Owns the write pipeline (validate, serialize, etag-check, write, audit)
      # extracted from Store::Writer. Talks to ports (FileStore, Schemas,
      # AuditLog, Manifest) instead of File/FileUtils and Store directly.
      #
      # No permission check, no event firing — those belong to the caller
      # (Application::Writes::Put / ::Delete).
      class EnvelopeIO
        Payload = Data.define(:meta, :body, :content)

        def initialize(file_store:, manifest:, schemas:, audit_log:, ctx:)
          @file_store = file_store
          @manifest   = manifest
          @schemas    = schemas
          @audit_log  = audit_log
          @ctx        = ctx
        end

        def write(key, mentry:, payload:, if_etag: nil)
          path = @manifest.resolve(key).path

          meta = payload.meta || {}
          strategy = Entry.for_format(mentry.format)

          existing_uid = existing_uid_for(mentry, path)
          meta, content = ensure_uid(mentry.format, meta, payload.content, existing_uid)

          bytes, eff_meta, eff_body, eff_content = serialize_for_put(
            mentry: mentry, path: path, strategy: strategy,
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
          @audit_log.append(
            role: @ctx.role, verb: "put", key: key,
            etag_before: etag_before, etag_after: etag_after,
            extras: @ctx.correlation_id ? { "correlation_id" => @ctx.correlation_id } : nil
          )
          Envelope.build(
            key: key, mentry: mentry, path: path,
            meta: eff_meta, body: eff_body, etag: etag_after, content: eff_content
          )
        end

        def delete(key, mentry:, if_etag: nil)
          _ = mentry
          path = @manifest.resolve(key).path
          raise UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)) unless @file_store.exists?(path)

          etag_before = @file_store.etag(path)
          raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

          @file_store.delete(path)
          @audit_log.append(
            role: @ctx.role, verb: "delete", key: key,
            etag_before: etag_before, etag_after: nil,
            extras: @ctx.correlation_id ? { "correlation_id" => @ctx.correlation_id } : nil
          )
        end

        private

        def existing_uid_for(mentry, path)
          return nil unless @file_store.exists?(path)

          raw = @file_store.read(path)
          parsed = Entry.for_format(mentry.format).parse(raw, path: path)
          Envelope.extract_uid(parsed["_meta"])
        rescue StandardError
          nil
        end

        def ensure_uid(format, meta, content, existing_uid)
          Textus::Entry.for_format(format).inject_uid(meta, content, existing_uid)
        end

        def enforce_name_match!(path, meta, format)
          Textus::Entry.for_format(format).enforce_name_match!(path, meta)
        end

        def serialize_for_put(mentry:, path:, strategy:, meta:, body:, content:)
          _ = strategy
          Textus::Entry.for_format(mentry.format).serialize_for_put(
            meta: meta, body: body, content: content, path: path,
          )
        end
      end
    end
  end
end
