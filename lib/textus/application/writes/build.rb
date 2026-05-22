module Textus
  module Application
    module Writes
      class Build
        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def call(prefix: nil)
          # Delegate to legacy Builder for the materialization/projection logic.
          # Builder fires its own events through @store.fire_event; we do NOT
          # double-fire from here. Full extraction of Builder internals into
          # Writes::Build is deferred to 0.10.0.
          #
          # TODO(0.10.0): propagate @ctx.correlation_id through :built/:published
          # events once Builder internals are extracted into this use case.
          legacy = Textus::Builder.new(@ctx.store)
          legacy.build(prefix: prefix)
        end
      end
    end
  end
end
