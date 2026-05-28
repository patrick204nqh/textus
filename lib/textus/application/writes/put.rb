module Textus
  module Application
    module Writes
      module Put
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(
            ctx: ctx, caps: caps,
            writer: session.envelope_writer,
            hook_context: session.hook_context
          ).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, writer:, hook_context:)
            @ctx          = ctx
            @manifest     = caps.manifest
            @events       = caps.events
            @authorizer   = caps.authorizer
            @writer       = writer
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
end

Textus::Application::UseCase.register(:put, Textus::Application::Writes::Put, caps: :write)
