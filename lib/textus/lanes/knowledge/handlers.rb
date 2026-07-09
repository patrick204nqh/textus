module Textus
  module Lanes
    module Knowledge
      module Handlers
        module_function

        def loop(ctx:, call:)
          runner = Runner.new(ctx.manifest)
          nodes = runner.loop_nodes.map { |e| { "name" => e.key.delete_prefix("knowledge.loop."), "key" => e.key } }
          feedback = recent_feedback(ctx)
          {
            "loop" => nodes,
            "count" => nodes.size,
            "flow" => runner.flow,
            "feedback" => feedback,
          }
        end

        def recent_feedback(ctx)
          rows = ctx.entry_index&.search(schema: "loop-feedback", lane: "knowledge", query: nil, under: nil)
          return [] unless rows&.any?

          rows.map do |row|
            env = ctx.read(key: row["key"])
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
