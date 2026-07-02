module Textus
  module UseCases
    module Read
      module GraphEntry
        HANDLES = Dispatch::Contracts::GraphEntry
        NEEDS = %i[link_graph].freeze

        def self.call(command, _call, deps)
          from = deps.link_graph.links_from(command.key)
          to   = deps.link_graph.links_to(command.key)
          neighbors = (from + to).uniq
          reachable = deps.link_graph.reachable(from: command.key, depth: command.depth)
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
