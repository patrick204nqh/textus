module Textus
  module Protocol
    class StoreEngine
      module PutPipeline
        module Prepare
          def self.call(ctx, deps)
            ctx = read_existing(ctx, deps)
            ctx = inject_meta(ctx, deps)
            serialize(ctx, deps)
          end

          def self.read_existing(ctx, deps)
            return ctx.with(existing_env: nil) unless ctx.path && deps.file_system.exists?(ctx.path)

            raw = deps.file_system.read(ctx.path)
            parsed = Textus::Protocol::Format.for(ctx.format).parse(raw, path: ctx.path)
            envelope = Textus::Protocol::Envelope.build(
              key: ctx.key, mentry: ctx.mentry, path: ctx.path,
              meta: parsed["_meta"] || {},
              body: parsed["body"] || "",
              content: parsed["content"],
              etag: Textus::Value::Etag.for_file(ctx.path)
            )
            ctx.with(existing_env: envelope)
          end

          def self.inject_meta(ctx, deps)
            existing_meta = ctx.existing_env ? ctx.existing_env.meta : {}
            raw_meta = ctx.payload.meta || {}
            meta, content = Textus::Infra::Store::Envelope::Meta.inject_all(
              raw_meta, ctx.payload.content, existing_meta,
              format: ctx.format,
              etag_for: method(:resolve_source_etag).curry.call(deps)
            )
            ctx.with(meta:, content:)
          end

          def self.resolve_source_etag(deps, key)
            path = deps.manifest.resolver.resolve(key).path
            return nil unless deps.file_system.exists?(path)

            Textus::Value::Etag.for_file(path)
          rescue Textus::Error
            nil
          end

          def self.serialize(ctx, _deps)
            bytes, eff_meta, eff_body, eff_content =
              Textus::Protocol::Format.for(ctx.format).serialize_for_put(
                meta: ctx.meta, body: ctx.payload.body,
                content: ctx.content, path: ctx.path
              )
            ctx.with(bytes:, eff_meta:, eff_body:, eff_content:)
          end
        end
      end
    end
  end
end
