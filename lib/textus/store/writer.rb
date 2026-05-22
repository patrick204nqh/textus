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

      # Backward-compat shim — orchestration now lives in Application::Writes::Put.
      def put(key, meta: nil, body: nil, content: nil, if_etag: nil, as: Role::DEFAULT, suppress_events: false)
        ctx = Textus::Application::Context.new(store: @store, role: as)
        Textus::Application::Writes::Put.new(ctx: ctx, bus: @store.bus).call(
          key, meta: meta, body: body, content: content, if_etag: if_etag, suppress_events: suppress_events
        )
      end

      # Pure I/O: validate, serialize, etag-check, write to disk, audit. No
      # permission check and no event firing — those are handled by the caller
      # (Application::Writes::Put).
      def write_envelope_to_disk(key, mentry:, meta: nil, body: nil, content: nil, if_etag: nil, as: Role::DEFAULT, correlation_id: nil)
        _, path, = @manifest.resolve(key)

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
          role: as, verb: "put", key: key,
          etag_before: etag_before, etag_after: etag_after,
          extras: correlation_id ? { "correlation_id" => correlation_id } : nil
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

      # Backward-compat shim — orchestration now lives in Application::Writes::Delete.
      def delete(key, if_etag: nil, as: Role::DEFAULT, suppress_events: false)
        ctx = Textus::Application::Context.new(store: @store, role: as)
        Textus::Application::Writes::Delete.new(ctx: ctx, bus: @store.bus).call(
          key, if_etag: if_etag, suppress_events: suppress_events
        )
      end

      # Pure I/O: resolve path, validate etag, delete from disk, audit. No
      # permission check and no event firing — those are handled by the caller
      # (Application::Writes::Delete).
      def delete_envelope_from_disk(key, if_etag: nil, as: Role::DEFAULT, correlation_id: nil)
        _, path, = @manifest.resolve(key)
        raise UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)) unless File.exist?(path)

        etag_before = Etag.for_file(path)
        raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

        File.delete(path)
        @store.audit_log.append(
          role: as, verb: "delete", key: key,
          etag_before: etag_before, etag_after: nil,
          extras: correlation_id ? { "correlation_id" => correlation_id } : nil
        )
      end

      def accept(key, as:)
        Proposal.accept(@store, key, as: as)
      end

      def reject(pending_key, as: Role::DEFAULT)
        raise ProposalError.new("only human role can reject proposals; got '#{as}'") unless as == "human"

        mentry, = @store.manifest.resolve(pending_key)
        raise ProposalError.new("reject: '#{pending_key}' is not a pending entry (zone=#{mentry.zone})") unless mentry.zone == "pending"

        env = @store.get(pending_key)
        proposal = env.dig("_meta", "proposal") or
          raise ProposalError.new("entry has no proposal block: #{pending_key}")
        target_key = proposal["target_key"] or raise ProposalError.new("proposal missing target_key")

        delete(pending_key, as: as)
        @store.fire_event(:reject, key: pending_key, target_key: target_key)
        { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
      end
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
