module Textus
  module Handlers
    module Read
      module WhereEntry
        HANDLES = Dispatch::Contracts::WhereEntry
        NEEDS   = %i[manifest].freeze

        def self.call(command, _call, deps)
          res = deps.manifest.resolver.resolve(command.key)
          mentry = res.entry
          Value::Result.success("protocol" => Textus::PROTOCOL, "key" => command.key,
                                "lane" => mentry.lane, "owner" => mentry.owner, "path" => res.path)
        end
      end
    end
  end
end
