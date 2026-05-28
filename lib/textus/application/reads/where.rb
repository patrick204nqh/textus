module Textus
  module Application
    module Reads
      class Where
        def initialize(ports:)
          @manifest = ports.manifest
        end

        def call(key)
          res = @manifest.resolver.resolve(key)
          mentry = res.entry
          path = res.path
          { "protocol" => PROTOCOL, "key" => key, "zone" => mentry.zone, "owner" => mentry.owner, "path" => path }
        end
      end
    end
  end
end
