module Textus
  module Application
    module Writes
      class Delete
        def initialize(ctx:, ports:, writer:, authorizer:, hook_context:)
          @ctx          = ctx
          @manifest     = ports.manifest
          @bus          = ports.event_bus
          @writer       = writer
          @authorizer   = authorizer
          @hook_context = hook_context
        end

        def call(key, if_etag: nil, suppress_events: false)
          Textus::Manifest::Data.validate_key!(key)
          mentry = @manifest.resolver.resolve(key).entry

          @authorizer.authorize_write!(mentry, role: @ctx.role)

          @writer.delete(key, mentry: mentry, if_etag: if_etag)

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
