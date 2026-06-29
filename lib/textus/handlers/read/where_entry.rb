module Textus
  module Handlers
    module Read
      class WhereEntry
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(command, _call)
          res = @manifest.resolver.resolve(command.key)
          mentry = res.entry
          Value::Result.success("protocol" => Textus::PROTOCOL, "key" => command.key,
                                "lane" => mentry.lane, "owner" => mentry.owner, "path" => res.path)
        end
      end
    end
  end
end
