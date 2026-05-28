module Textus
  module Application
    module Writes
      class Put
        def initialize(ctx:, manifest:, envelope_io:, bus:, authorizer:, hook_context:)
          @ctx          = ctx
          @manifest     = manifest
          @envelope_io  = envelope_io
          @bus          = bus
          @authorizer   = authorizer
          @hook_context = hook_context
        end

        def call(key, meta: nil, body: nil, content: nil, if_etag: nil)
          Textus::Manifest::Data.validate_key!(key)
          mentry = @manifest.resolver.resolve(key).entry

          @authorizer.authorize_write!(mentry, role: @ctx.role)

          envelope = @envelope_io.write(
            key,
            mentry: mentry,
            payload: Textus::Application::Writes::EnvelopeIO::Payload.new(meta: meta, body: body, content: content),
            if_etag: if_etag,
          )

          @bus.publish(:entry_put,
                       ctx: @hook_context,
                       key: key,
                       envelope: envelope)

          envelope
        end
      end
    end
  end
end
