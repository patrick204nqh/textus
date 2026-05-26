module Textus
  module Application
    module Writes
      class Put
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key, meta: nil, body: nil, content: nil, if_etag: nil, suppress_events: false)
          @ctx.store.manifest.validate_key!(key)
          mentry = @ctx.store.manifest.resolve(key).entry

          @ctx.authorize_write!(mentry)

          envelope = @ctx.store.writer.write_envelope_to_disk(
            key,
            mentry: mentry,
            payload: Textus::Store::Writer::Payload.new(meta: meta, body: body, content: content),
            ctx: @ctx,
            if_etag: if_etag,
          )

          unless suppress_events
            @ctx.bus.publish(:entry_put,
                             store: @ctx.with_role(@ctx.role),
                             key: key,
                             envelope: envelope,
                             correlation_id: @ctx.correlation_id)
          end

          envelope
        end
      end
    end
  end
end
