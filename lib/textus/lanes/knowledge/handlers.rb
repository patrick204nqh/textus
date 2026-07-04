module Textus
  module Lanes
    module Knowledge
      module Handlers
        module_function

        def loop(store:, ctx:, call:)
          nodes = ctx.manifest.data.entries
                     .select { |e| e.key.start_with?("knowledge.loop.") && e.key.count(".") == 2 }
                     .map { |e| { "name" => e.key.split(".").last, "key" => e.key } }
          role = call&.role || "agent"
          runner = Runner.new(ctx.manifest, cursor_store: store.cursor_store)
          feedback = recent_feedback(store)
          {
            "loop" => nodes,
            "count" => nodes.size,
            "flow" => runner.flow,
            "current_node" => runner.current_position(role),
            "feedback" => feedback,
          }
        end

        def recent_feedback(store)
          rows = store.entry_index&.search(schema: "loop-feedback", lane: "knowledge", query: nil, prefix: nil)
          return [] unless rows&.any?

          rows.map do |row|
            env = store.read(row["key"])
            meta = env&.meta || {}
            {
              "key" => row["key"],
              "node" => meta["node"],
              "confidence" => meta["confidence"],
              "signal" => meta["signal"],
              "summary" => env&.body || meta["summary"],
            }
          end
        rescue Textus::Error
          []
        end
      end
    end
  end
end
