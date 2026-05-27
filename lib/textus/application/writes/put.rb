module Textus
  module Application
    module Writes
      class Put
        def initialize(ctx:, manifest:, envelope_io:, bus:, authorizer:, store:)
          @ctx         = ctx
          @manifest    = manifest
          @envelope_io = envelope_io
          @bus         = bus
          @authorizer  = authorizer
          @store       = store
        end

        def call(key, meta: nil, body: nil, content: nil, if_etag: nil, suppress_events: false)
          @manifest.validate_key!(key)
          mentry = @manifest.resolve(key).entry

          @authorizer.authorize_write!(mentry, role: @ctx.role)

          envelope = @envelope_io.write(
            key,
            mentry: mentry,
            payload: Textus::Application::Writes::EnvelopeIO::Payload.new(meta: meta, body: body, content: content),
            if_etag: if_etag,
          )

          unless suppress_events
            @bus.publish(:entry_put,
                         store: @store,
                         role: @ctx.role,
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
