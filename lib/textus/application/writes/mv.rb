module Textus
  module Application
    module Writes
      class Mv
        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def call(old_key, new_key, dry_run: false)
          mover = Textus::Store::Mover.new(
            store: @ctx.store,
            reader: @ctx.store.reader,
            writer: @ctx.store.writer,
            manifest: @ctx.store.manifest,
            audit_log: @ctx.store.audit_log,
          )
          mover.call(old_key, new_key, as: @ctx.role, dry_run: dry_run, correlation_id: @ctx.correlation_id)
        end
      end
    end
  end
end
