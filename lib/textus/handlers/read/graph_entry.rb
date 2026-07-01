module Textus
  module Handlers
    module Read
      module GraphEntry
        HANDLES = Dispatch::Contracts::GraphEntry
        NEEDS   = %i[link_edge_store].freeze

        def self.call(command, _call, deps)
          neighbors  = deps.link_edge_store.neighbors_of(command.key)
          reachable  = deps.link_edge_store.reachable(command.key, depth: command.depth)
          Value::Result.success(
            "key" => command.key,
            "neighbors" => neighbors.sort,
            "reachable" => reachable.sort,
          )
        end
      end
    end
  end
end
