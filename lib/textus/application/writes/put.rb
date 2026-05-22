module Textus
  module Application
    module Writes
      class Put
        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def call(key, meta: nil, body: nil, content: nil, if_etag: nil, suppress_events: false)
          @ctx.store.manifest.validate_key!(key)
          mentry, = @ctx.store.manifest.resolve(key)

          unless @ctx.can_write?(mentry.zone)
            raise WriteForbidden.new(key, mentry.zone,
                                     writers: @ctx.store.manifest.zone_writers(mentry.zone))
          end

          envelope = @ctx.store.writer.write_envelope_to_disk(
            key,
            mentry: mentry,
            meta: meta,
            body: body,
            content: content,
            if_etag: if_etag,
            as: @ctx.role,
            correlation_id: @ctx.correlation_id,
          )

          unless suppress_events
            store_view = Store::View.new(@ctx.store)
            @bus.publish(:put,
                         store: store_view,
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
