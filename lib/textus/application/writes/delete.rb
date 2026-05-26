module Textus
  module Application
    module Writes
      class Delete
        def initialize(ctx:, envelope_io:)
          @ctx = ctx
          @envelope_io = envelope_io
        end

        def call(key, if_etag: nil, suppress_events: false)
          @ctx.manifest.validate_key!(key)
          mentry = @ctx.manifest.resolve(key).entry

          @ctx.authorize_write!(mentry)

          @envelope_io.delete(key, mentry: mentry, if_etag: if_etag)

          unless suppress_events
            @ctx.bus.publish(:entry_deleted,
                             store: @ctx.with_role(@ctx.role),
                             key: key,
                             correlation_id: @ctx.correlation_id)
          end

          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
        end
      end
    end
  end
end
