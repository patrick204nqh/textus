require "fileutils"

module Textus
  class Store
    # rubocop:disable Metrics/ParameterLists
    class Writer
      def initialize(store)
        @store = store
        @manifest = store.manifest
        @reader = store.reader
      end

      def put(key, meta: nil, body: nil, content: nil, if_etag: nil, as: Role::DEFAULT, suppress_events: false)
        @manifest.validate_key!(key)
        mentry, path, = @manifest.resolve(key)
        writers = @manifest.zone_writers(mentry.zone)
        raise WriteForbidden.new(key, mentry.zone, writers: writers) unless writers.include?(as)

        meta ||= {}
        strategy = Entry.for_format(mentry.format)

        existing_uid = existing_uid_for(mentry, path)
        meta, content = ensure_uid(mentry.format, meta, content, existing_uid)

        bytes, eff_meta, eff_body, eff_content = serialize_for_put(
          mentry: mentry, path: path, strategy: strategy,
          meta: meta, body: body, content: content
        )

        enforce_name_match!(path, eff_meta, mentry.format)

        schema = @store.schema_for(mentry.schema)
        if schema
          case mentry.format
          when "markdown" then schema.validate!(eff_meta)
          when "json", "yaml" then schema.validate!(eff_content || {})
          end
        end

        etag_before = File.exist?(path) ? Etag.for_file(path) : nil
        raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && (etag_before != if_etag)

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, bytes)
        etag_after = Etag.for_bytes(bytes)
        @store.audit_log.append(role: as, verb: "put", key: key, etag_before: etag_before, etag_after: etag_after)
        envelope = Envelope.build(
          key: key, mentry: mentry, path: path,
          meta: eff_meta, body: eff_body, etag: etag_after, content: eff_content
        )
        @store.fire_event(:put, key: key, envelope: envelope) unless suppress_events
        envelope
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
        case format
        when "markdown", "json", "yaml"
          m = meta.is_a?(Hash) ? meta.dup : {}
          m["uid"] = existing_uid || Store.mint_uid unless m["uid"].is_a?(String) && !m["uid"].empty?
          [m, content]
        else
          [meta, content]
        end
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

      def delete(key, if_etag: nil, as: Role::DEFAULT, suppress_events: false)
        mentry, path, = @manifest.resolve(key)
        writers = @manifest.zone_writers(mentry.zone)
        raise WriteForbidden.new(key, mentry.zone, writers: writers) unless writers.include?(as)
        raise UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)) unless File.exist?(path)

        etag_before = Etag.for_file(path)
        raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

        File.delete(path)
        @store.audit_log.append(role: as, verb: "delete", key: key, etag_before: etag_before, etag_after: nil)
        @store.fire_event(:delete, key: key) unless suppress_events
        { "protocol" => PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
      end

      def accept(key, as:)
        Proposal.accept(@store, key, as: as)
      end
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
