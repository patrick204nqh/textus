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
        return unless %w[markdown json yaml].include?(format)
        return unless meta.is_a?(Hash) && meta["name"]

        ext = Entry.for_format(format).extensions.first
        basename = File.basename(path, ext)
        return if meta["name"] == basename

        raise BadFrontmatter.new(path, "name '#{meta["name"]}' does not match basename '#{basename}'")
      end

      def serialize_for_put(mentry:, path:, strategy:, meta:, body:, content:)
        case mentry.format
        when "markdown", "text"
          bytes = strategy.serialize(meta: meta, body: body.to_s)
          [bytes, meta, body.to_s, nil]
        when "json", "yaml"
          raise UsageError.new("put for #{mentry.format} requires content: or body:") if content.nil? && (body.nil? || body.to_s.empty?)

          if content.nil?
            begin
              parsed = strategy.parse(body.to_s, path: path)
            rescue BadFrontmatter => e
              raise BadContent.new(path, "bad_content: #{e.message}")
            end
            [body.to_s, parsed["_meta"], body.to_s, parsed["content"]]
          else
            bytes = strategy.serialize(meta: meta, body: "", content: content)
            [bytes, meta, bytes, content]
          end
        else
          raise UsageError.new("unknown format #{mentry.format.inspect}")
        end
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
