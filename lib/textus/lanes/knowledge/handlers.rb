module Textus
  module Lanes
    module Knowledge
      module Handlers
        module_function

        LOOP_NODE_KEYS = {
          "intent" => "knowledge.loop.intent",
          "constraint.repo" => "knowledge.loop.constraint.repo",
          "constraint.protocol" => "knowledge.loop.constraint.protocol",
          "judgment.engineering" => "knowledge.loop.judgment.engineering",
          "judgment.agent-behavior" => "knowledge.loop.judgment.agent-behavior",
          "evidence" => "knowledge.loop.evidence",
          "execution" => "knowledge.loop.execution.runbook",
          "adoption" => "knowledge.loop.adoption",
        }.freeze

        def loop(ctx:, call:)
          nodes = LOOP_NODE_KEYS.map { |name, key| { "name" => name, "key" => key } }
          role = call&.role || "agent"
          runner = Runner.new(ctx.manifest, cursor_store: ctx.cursor_store)
          feedback = recent_feedback(ctx)
          {
            "loop" => nodes,
            "count" => nodes.size,
            "flow" => runner.flow,
            "current_node" => runner.current_position(role),
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
