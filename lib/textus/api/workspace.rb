module Textus
  class API
    class Workspace
      def initialize(store_engine)
        @store = store_engine
      end

      def create(session_id, role:)
        return unless role == "agent"

        key = "scratchpad.sessions.#{session_id}"
        @store.put(key:, data: JSON.generate({
          session_id:, role:, status: "active",
          created_at: Time.now.utc.iso8601,
        }))
      end

      def close(session_id, loop_status: nil, nodes_checked: nil)
        key = "scratchpad.sessions.#{session_id}"
        env = @store.get(key:) rescue nil
        return unless env

        current = JSON.parse(env["body"] || "{}")
        feedback = {
          node: "feedback", confidence: "medium",
          signal: "session_closed",
          summary: "Session #{session_id[0..8]} sealed.",
        }
        feedback[:loop] = loop_status if loop_status
        feedback[:nodes_checked] = nodes_checked if nodes_checked

        content = current.merge(
          "status" => "sealed", "closed_at" => Time.now.utc.iso8601,
          "feedback" => feedback,
        )
        @store.put(key:, data: JSON.generate(content))
      end
    end
  end
end
