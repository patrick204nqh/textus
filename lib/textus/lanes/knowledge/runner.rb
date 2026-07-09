module Textus
  module Lanes
    module Knowledge
      class Runner
        def initialize(manifest)
          @manifest = manifest
        end

        def loop_nodes
          @manifest.data.entries.select do |e|
            e.key.start_with?("knowledge.loop.") && e.key != "knowledge.loop"
          end
        end

        def flow
          loop_nodes.map { |e| e.key.split(".").last }
        end
      end
    end
  end
end
