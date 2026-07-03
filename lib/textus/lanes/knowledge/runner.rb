module Textus
  module Lanes
    module Knowledge
      class Runner
        def initialize(manifest)
          @manifest = manifest
        end

        def loop_nodes
          @manifest.data.entries.select do |e|
            e.key.start_with?("knowledge.loop.") && e.key.count(".") == 2
          end
        end

        def flow
          loop_nodes.map { |e| e.key.split(".").last }
        end

        def current_node(active_index: 0)
          nodes = loop_nodes
          return nil if nodes.empty?

          idx = active_index % nodes.size
          { name: nodes[idx].key.split(".").last, index: idx, total: nodes.size }
        end

        def advance(active_index: 0)
          current_node(active_index: active_index + 1).merge(advanced: true)
        end
      end
    end
  end
end