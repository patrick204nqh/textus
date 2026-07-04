module Textus
  module Lanes
    module Knowledge
      module Handlers
        module_function

        def loop(ctx:, call:)
          nodes = ctx.manifest.data.entries
                     .select { |e| e.key.start_with?("knowledge.loop.") && e.key.count(".") == 2 }
                     .map { |e| { "name" => e.key.split(".").last, "key" => e.key } }
          { "loop" => nodes, "count" => nodes.size }
        end
      end
    end
  end
end
