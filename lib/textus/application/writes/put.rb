module Textus
  module Application
    module Writes
      class Put
        def initialize(ctx:, envelope_io:)
          @ctx = ctx
          @envelope_io = envelope_io
        end

        def call(key, meta: nil, body: nil, content: nil, if_etag: nil, suppress_events: false)
          @ctx.manifest.validate_key!(key)
          mentry = @ctx.manifest.resolve(key).entry

          @ctx.authorize_write!(mentry)

          envelope = @envelope_io.write(
            key,
            mentry: mentry,
            payload: Textus::Application::Writes::EnvelopeIO::Payload.new(meta: meta, body: body, content: content),
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
