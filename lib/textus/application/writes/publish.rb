module Textus
  module Application
    module Writes
      class Publish
        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def call(source:, target:, key:)
          Textus::Infra::Publisher.publish(
            source: source,
            target: target,
            store_root: @ctx.store.root,
          )
          @bus.publish(:published,
                       key: key,
                       source: source,
                       target: target,
                       correlation_id: @ctx.correlation_id)
        end
      end
    end
  end
end
