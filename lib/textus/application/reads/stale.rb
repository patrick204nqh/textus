module Textus
  module Application
    module Reads
      class Stale
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(prefix: nil, zone: nil)
          Textus::Domain::Staleness.new(manifest: @ctx.manifest).call(prefix: prefix, zone: zone)
        end
      end
    end
  end
end
