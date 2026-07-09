module Textus
  module Protocol
    class StoreEngine
      module Put
        module_function

        def call(key, mentry:, path:, payload:, deps:, if_etag: nil, fmt: nil)
          format = fmt || mentry.format

          validate_input(key, payload, format, mentry, path)
          validate_schema(key, payload, mentry, deps)

          existing_env = read_existing(key, mentry, path, format, deps)
          meta, content = inject_meta(payload, existing_env, format, deps)
          bytes, eff_meta, eff_body, eff_content = serialize(payload, meta, content, path, format)

          etag_before = Pipeline.check_etag(key, path, if_etag, deps.file_system)
          deps.file_system.write(path, bytes)
          envelope = Envelope.build(
            key:, mentry:, path:,
            meta: eff_meta, body: eff_body,
            etag: Value::Etag.for_bytes(bytes),
            content: eff_content
          )

          append_audit(key, etag_before, envelope, deps)
          index_entry(key, mentry, format, eff_body, eff_content, deps)
          Pipeline.emit_event(deps, event_type: "entry.written",
                                    pending_key: key, emit_key: key,
                                    emit_lane: mentry.lane)
          envelope
        end

        def validate_input(key, payload, format, mentry, path)
          fmt = Format.for(format)
          fmt.enforce_name_match!(path, payload.meta)
          fmt.validate_raw_entry!(
            { "_meta" => payload.meta, "content" => payload.content },
            mentry.lane,
          )
        end

        def validate_schema(key, payload, mentry, deps)
          blueprint_errors = Protocol::Blueprint::Controller.validate(
            key, payload, schemas: deps.schemas, manifest: deps.manifest
          )
          unless blueprint_errors.empty?
            raise Textus::UsageError.new(blueprint_errors.join("; "))
          end
        end

        def read_existing(key, mentry, path, format, deps)
          return nil unless path && deps.file_system.exists?(path)

          raw = deps.file_system.read(path)
          parsed = Format.for(format).parse(raw, path:)
          Envelope.build(
            key:, mentry:, path:,
            meta: parsed["_meta"] || {},
            body: parsed["body"] || "",
            content: parsed["content"],
            etag: Value::Etag.for_file(path)
          )
        end

        def inject_meta(payload, existing_env, format, deps)
          existing_meta = existing_env ? existing_env.meta : {}
          Infra::Store::Envelope::Meta.inject_all(
            payload.meta || {}, payload.content, existing_meta,
            format:,
            etag_for: method(:etag_for_key).curry.call(deps)
          )
        end

        def etag_for_key(deps, key)
          path = deps.manifest.resolver.resolve(key).path
          return nil unless deps.file_system.exists?(path)

          Value::Etag.for_file(path)
        rescue Textus::Error
          nil
        end

        def serialize(payload, meta, content, path, format)
          Format.for(format).serialize_for_put(
            meta:, body: payload.body, content:, path:,
          )
        end

        def append_audit(key, etag_before, envelope, deps)
          deps.audit_log.append(
            role: deps.call.role, verb: "put", key:,
            etag_before:, etag_after: envelope.etag,
            correlation_id: deps.call.correlation_id
          )
        end

        def index_entry(key, mentry, format, eff_body, eff_content, deps)
          content = eff_content ? eff_content.to_json : eff_body
          deps.entry_index.record(
            key:, lane: mentry.lane, format:,
            schema: mentry.schema, content:
          )
        end
      end
    end
  end
end
