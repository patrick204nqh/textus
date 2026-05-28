module Textus
  module Application
    module Writes
      class Put
        def initialize(ctx:, ports:, writer:, authorizer:, hook_context:)
          @ctx          = ctx
          @manifest     = ports.manifest
          @events       = ports.event_bus
          @writer       = writer
          @authorizer   = authorizer
          @hook_context = hook_context
        end

        def call(key, meta: nil, body: nil, content: nil, if_etag: nil)
          Textus::Manifest::Data.validate_key!(key)
          mentry = @manifest.resolver.resolve(key).entry

          @authorizer.authorize_write!(mentry, role: @ctx.role)

          envelope = @writer.put(
            key,
            mentry: mentry,
            payload: Textus::Application::Envelope::Writer::Payload.new(meta: meta, body: body, content: content),
            if_etag: if_etag,
          )

          @events.publish(:entry_put,
                          ctx: @hook_context,
                          key: key,
                          envelope: envelope)

          envelope
        end
      end
    end
  end
end
