module Textus
  module Protocol
    class StoreEngine
      module PutPipeline
        module Write
          def self.call(ctx, deps)
            ctx = check_etag(ctx, deps)
            ctx = write_bytes(ctx, deps)
            build_envelope(ctx, deps)
          end

          private

          def self.check_etag(ctx, deps)
            Pipeline.check_etag(ctx, deps)
          end

          def self.write_bytes(ctx, deps)
            deps.file_system.write(ctx.path, ctx.bytes)
            ctx
          end

          def self.build_envelope(ctx, deps)
            envelope = Textus::Protocol::Envelope.build(
              key: ctx.key, mentry: ctx.mentry, path: ctx.path,
              meta: ctx.eff_meta, body: ctx.eff_body,
              etag: Textus::Value::Etag.for_bytes(ctx.bytes),
              content: ctx.eff_content
            )
            ctx.with(envelope:)
          end
        end
      end
    end
  end
end
