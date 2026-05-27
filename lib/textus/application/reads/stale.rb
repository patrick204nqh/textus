module Textus
  module Application
    module Reads
      class Stale
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(prefix: nil, zone: nil)
          Textus::Domain::Staleness.new(manifest: @manifest).call(prefix: prefix, zone: zone)
        end
      end
    end
  end
end
