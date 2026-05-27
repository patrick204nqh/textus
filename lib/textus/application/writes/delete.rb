module Textus
  module Application
    module Writes
      class Delete
        def initialize(ctx:, manifest:, envelope_io:, bus:, authorizer:, store:)
          @ctx         = ctx
          @manifest    = manifest
          @envelope_io = envelope_io
          @bus         = bus
          @authorizer  = authorizer
          @store       = store
        end

        def call(key, if_etag: nil, suppress_events: false)
          @manifest.validate_key!(key)
          mentry = @manifest.resolve(key).entry

          @authorizer.authorize_write!(mentry, role: @ctx.role)

          @envelope_io.delete(key, mentry: mentry, if_etag: if_etag)

          unless suppress_events
            @bus.publish(:entry_deleted,
                         store: @store,
                         role: @ctx.role,
                         key: key,
                         correlation_id: @ctx.correlation_id)
          end

          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
        end
      end
    end
  end
end
