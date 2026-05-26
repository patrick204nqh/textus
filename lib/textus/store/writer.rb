require "fileutils"

module Textus
  class Store
    class Writer
      Payload = Data.define(:meta, :body, :content)

      def initialize(store)
        @store = store
        @manifest = store.manifest
        @reader = store.reader
      end

      # Pure I/O: validate, serialize, etag-check, write to disk, audit. No
      # permission check and no event firing — those are handled by the caller
      # (Application::Writes::Put).
      def write_envelope_to_disk(key, mentry:, payload:, ctx:, if_etag: nil)
        _, path, = @manifest.resolve(key)

        meta = payload.meta || {}
        strategy = Entry.for_format(mentry.format)

        existing_uid = existing_uid_for(mentry, path)
        meta, content = ensure_uid(mentry.format, meta, payload.content, existing_uid)

        bytes, eff_meta, eff_body, eff_content = serialize_for_put(
          mentry: mentry, path: path, strategy: strategy,
          meta: meta, body: payload.body, content: content
        )

        enforce_name_match!(path, eff_meta, mentry.format)

        schema = @store.schema_for(mentry.schema)
        if schema
          Entry.for_format(mentry.format).validate_against(
            schema,
            { "_meta" => eff_meta, "content" => eff_content },
          )
        end

        etag_before = File.exist?(path) ? Etag.for_file(path) : nil
        raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && (etag_before != if_etag)

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, bytes)
        etag_after = Etag.for_bytes(bytes)
        @store.audit_log.append(
          role: ctx.role, verb: "put", key: key,
          etag_before: etag_before, etag_after: etag_after,
          extras: ctx.correlation_id ? { "correlation_id" => ctx.correlation_id } : nil
        )
        Envelope.build(
          key: key, mentry: mentry, path: path,
          meta: eff_meta, body: eff_body, etag: etag_after, content: eff_content
        )
      end

      def existing_uid_for(mentry, path)
        return nil unless File.exist?(path)

        raw = File.binread(path)
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

      # Pure I/O: resolve path, validate etag, delete from disk, audit. No
      # permission check and no event firing — those are handled by the caller
      # (Application::Writes::Delete).
      def delete_envelope_from_disk(key, ctx:, if_etag: nil)
        _, path, = @manifest.resolve(key)
        raise UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)) unless File.exist?(path)

        etag_before = Etag.for_file(path)
        raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

        File.delete(path)
        @store.audit_log.append(
          role: ctx.role, verb: "delete", key: key,
          etag_before: etag_before, etag_after: nil,
          extras: ctx.correlation_id ? { "correlation_id" => ctx.correlation_id } : nil
        )
      end
    end
  end
end
