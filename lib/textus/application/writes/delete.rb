module Textus
  module Application
    module Writes
      class Delete
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key, if_etag: nil, suppress_events: false)
          @ctx.store.manifest.validate_key!(key)
          mentry = @ctx.store.manifest.resolve(key).entry

          @ctx.authorize_write!(mentry)

          @ctx.store.writer.delete_envelope_from_disk(
            key, ctx: @ctx, if_etag: if_etag
          )

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
