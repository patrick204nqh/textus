module Textus
  module UseCases
    module Read
      class GraphEntry < Base
        handles Dispatch::Contracts::GraphEntry
        needs :link_graph

        def call
          from = @link_graph.links_from(@command.key)
          to   = @link_graph.links_to(@command.key)
          neighbors = (from + to).uniq
          reachable = @link_graph.reachable(from: @command.key, depth: @command.depth)
          success(
            "key" => @command.key,
            "neighbors" => neighbors.sort,
            "reachable" => reachable.sort,
          )
        end
      end
    end
  end
end
