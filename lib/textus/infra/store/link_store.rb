module Textus
  module Infra
    class Store
      class LinkStore
        def initialize(database)
          @db = database
        end

        def add_edge(from_key:, to_key:)
          @db[:link_edges].insert_ignore.insert(from_key:, to_key:)
        end
        alias record add_edge

        def remove_edge(from_key:, to_key:)
          @db[:link_edges].where(from_key:, to_key:).delete
        end

        def links_from(key)
          @db[:link_edges].where(from_key: key).select_map(:to_key)
        end

        def links_to(key)
          @db[:link_edges].where(to_key: key).select_map(:from_key)
        end

        def reachable(from:, depth: nil)
          visited = Set.new
          queue = [[from, 0]]
          while queue.any?
            current, d = queue.shift
            next if visited.include?(current)
            next if depth && d > depth

            visited.add(current)
            links_from(current).each { |to| queue << [to, d + 1] }
          end
          visited.delete(from)
          visited.to_a
        end
      end
    end
  end
end
