module Textus
  module Application
    module Writes
      class Delete
        def initialize(ctx:, manifest:, envelope_io:, bus:, authorizer:, hook_context:)
          @ctx          = ctx
          @manifest     = manifest
          @envelope_io  = envelope_io
          @bus          = bus
          @authorizer   = authorizer
          @hook_context = hook_context
        end

        def call(key, if_etag: nil, suppress_events: false)
          @manifest.validate_key!(key)
          mentry = @manifest.resolver.resolve(key).entry

          @authorizer.authorize_write!(mentry, role: @ctx.role)

          @envelope_io.delete(key, mentry: mentry, if_etag: if_etag)

          unless suppress_events
            @bus.publish(:entry_deleted,
                         ctx: @hook_context,
                         key: key)
          end

          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
        end
      end
    end
  end
end
